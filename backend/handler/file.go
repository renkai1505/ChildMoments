package handler

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/google/uuid"
	"github.com/kingwrcy/moments/db"
	"github.com/kingwrcy/moments/vo"
	"github.com/labstack/echo/v4"
	"github.com/rwcarlsen/goexif/exif"
	"github.com/samber/do/v2"
	"gorm.io/gorm"
)

type FileHandler struct {
	base BaseHandler
}

func NewFileHandler(injector do.Injector) *FileHandler {
	return &FileHandler{do.MustInvoke[BaseHandler](injector)}
}

// ExtractExifDateTime extracts the date and time from EXIF data
func ExtractExifDateTime(r io.Reader) (time.Time, error) {
	x, err := exif.Decode(r)
	if err != nil {
		return time.Time{}, err
	}

	dt, err := x.DateTime()
	if err != nil {
		return time.Time{}, err
	}

	return dt, nil
}

// Upload godoc
//
//	@Tags		File
//	@Summary	上传图片
//	@Accept		json
//	@Produce	json
//	@Param		x-api-token	header	string	true	"登录TOKEN"
//	@Success	200
//	@Router		/api/file/upload [post]
func (f FileHandler) Upload(c echo.Context) error {
	var (
		result    []string
		exifTimes []time.Time
	)

	form, err := c.MultipartForm()
	if err != nil {
		f.base.log.Error().Msgf("读取上传图片异常:%s", err)
		return FailRespWithMsg(c, Fail, "上传图片异常")
	}

	if err := os.MkdirAll(f.base.cfg.UploadDir, 0755); err != nil {
		f.base.log.Error().Msgf("创建父级目录异常:%s", err)
		return FailRespWithMsg(c, Fail, "创建父级目录异常")
	}

	files := form.File["files"]
	for _, file := range files {
		// 原始图片
		src, err := file.Open()
		if err != nil {
			f.base.log.Error().Msgf("打开上传图片异常:%s", err)
			return FailRespWithMsg(c, Fail, "上传图片异常")
		}

		// 尝试提取EXIF数据中的时间戳
		exifTime, err := ExtractExifDateTime(src)
		if err == nil {
			exifTimes = append(exifTimes, exifTime)
			f.base.log.Info().Msgf("成功从图片中提取EXIF时间: %s", exifTime)
		} else {
			f.base.log.Info().Msgf("无法从图片中提取EXIF时间: %s", err)
		}

		// 重置文件指针到开头
		src.Close()
		src, err = file.Open()
		if err != nil {
			f.base.log.Error().Msgf("重新打开上传图片异常:%s", err)
			return FailRespWithMsg(c, Fail, "上传图片异常")
		}
		defer src.Close()

		// 创建原始图片
		img_filename := strings.ReplaceAll(uuid.NewString(), "-", "")
		img_filepath := path.Join(f.base.cfg.UploadDir, img_filename)
		dst, err := os.Create(img_filepath)
		if err != nil {
			f.base.log.Error().Msgf("打开目标图片异常:%s", err)
			return FailRespWithMsg(c, Fail, "上传图片异常")
		}
		defer dst.Close()

		// 保存图片
		if _, err = io.Copy(dst, src); err != nil {
			f.base.log.Error().Msgf("复制图片异常:%s", err)
			return FailRespWithMsg(c, Fail, "上传图片异常")
		}

		// 生成并保存缩略图
		thumb_filename := img_filename + "_thumb"
		thumb_filepath := path.Join(f.base.cfg.UploadDir, thumb_filename)
		if err := CompressImage(f, img_filepath, thumb_filepath, 30); err != nil {
			f.base.log.Error().Msgf("压缩图片异常:%s", err)
		}

		result = append(result, "/upload/"+img_filename)
	}

	// 如果有EXIF时间，则返回最早的那个时间
	var oldestTime *time.Time
	if len(exifTimes) > 0 {
		oldest := exifTimes[0]
		for _, t := range exifTimes {
			if t.Before(oldest) {
				oldest = t
			}
		}
		oldestTime = &oldest
	}

	// 返回结果
	if oldestTime != nil {
		return SuccessResp(c, map[string]interface{}{
			"urls":     result,
			"exifTime": oldestTime,
		})
	} else {
		// 如果没有EXIF时间，则直接返回URL数组，保持向后兼容
		return SuccessResp(c, result)
	}
}

type PreSignedReq struct {
	ContentType string `json:"contentType,omitempty"` //图片mime类型
}

type s3PresignedResp struct {
	PreSignedUrl string `json:"preSignedUrl,omitempty"` //S3预签名上传地址
	ImageUrl     string `json:"imageUrl,omitempty"`     //实际的图片地址
}

// S3PreSigned godoc
//
//	@Tags		File
//	@Summary	S3预签名
//	@Accept		json
//	@Produce	json
//	@Param		object		body		PreSignedReq	true	"S3预签名"
//	@Param		x-api-token	header		string			true	"登录TOKEN"
//	@Success	200			{object}	s3PresignedResp
//	@Router		/api/file/s3PreSigned [post]
func (f FileHandler) S3PreSigned(c echo.Context) error {
	var (
		req         PreSignedReq
		sysConfig   db.SysConfig
		sysConfigVo vo.FullSysConfigVO
	)
	if err := c.Bind(&req); err != nil {
		return FailResp(c, ParamError)
	}

	if err := f.base.db.First(&sysConfig).Error; errors.Is(err, gorm.ErrRecordNotFound) {
		return FailResp(c, Fail)
	}

	if err := json.Unmarshal([]byte(sysConfig.Content), &sysConfigVo); err != nil {
		f.base.log.Error().Msgf("无法反序列化系统配置, %s", err)
		return FailRespWithMsg(c, Fail, err.Error())
	}

	cfg, err := config.LoadDefaultConfig(
		context.TODO(),
		config.WithRegion(sysConfigVo.S3.Region),
		config.WithEndpointResolver(
			aws.EndpointResolverFunc(
				func(service, region string) (aws.Endpoint, error) {
					return aws.Endpoint{URL: sysConfigVo.S3.Endpoint}, nil
				},
			),
		),
		config.WithCredentialsProvider(
			credentials.NewStaticCredentialsProvider(
				sysConfigVo.S3.AccessKey,
				sysConfigVo.S3.SecretKey,
				"",
			),
		),
	)
	if err != nil {
		f.base.log.Error().Msgf("无法加载SDK配置, %s", err)
		return FailRespWithMsg(c, Fail, err.Error())
	}

	client := s3.NewFromConfig(cfg)
	presignedClient := s3.NewPresignClient(client)

	key := fmt.Sprintf(
		"moments/%s/%s",
		time.Now().Format("2006/01/02"),
		strings.ReplaceAll(uuid.NewString(), "-", ""),
	)
	presignedResult, err := presignedClient.PresignPutObject(
		context.TODO(),
		&s3.PutObjectInput{
			Bucket:      aws.String(sysConfigVo.S3.Bucket),
			Key:         aws.String(key),
			ContentType: aws.String(req.ContentType),
		},
		func(opts *s3.PresignOptions) {
			opts.Expires = time.Minute * 5
		},
	)

	if err != nil {
		f.base.log.Error().Msgf("无法获取预签名URL, %s", err)
		return FailRespWithMsg(c, Fail, fmt.Sprintf("无法获取预签名URL, %s", err))
	}

	// 注意：对于S3上传，我们无法在此处提取EXIF时间，因为图片是直接上传到S3的
	// 前端需要使用本地文件的EXIF时间
	return SuccessResp(
		c,
		s3PresignedResp{
			PreSignedUrl: presignedResult.URL,
			ImageUrl:     fmt.Sprintf("%s/%s", sysConfigVo.S3.Domain, key),
		},
	)
}
