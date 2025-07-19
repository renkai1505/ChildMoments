package handler

import (
	"strconv"

	"github.com/kingwrcy/moments/db"
	"github.com/kingwrcy/moments/pkg/util"
	"github.com/labstack/echo/v4"
	"github.com/samber/do/v2"
)

type FriendHandler struct {
	base BaseHandler
}

func NewFriendHandler(injector do.Injector) *FriendHandler {
	return &FriendHandler{do.MustInvoke[BaseHandler](injector)}
}

type getFriendListResp struct {
	List []db.Friend `json:"list,omitempty"`
}

// 获取友情链接列表
// @Router /api/friend/list [post]
func (n FriendHandler) GetFriendList(c echo.Context) error {
	var friendList []db.Friend
	if err := n.base.db.Find(&friendList).Error; err != nil {
		n.base.log.Error().Msgf("获取友情列表失败, %v", err)
		return FailRespWithMsg(c, Fail, "读取友情链接列表失败")
	}

	return SuccessResp(c, getFriendListResp{
		List: friendList,
	})
}

// 添加友情链接
// @Router /api/friend/add [post]
func (n FriendHandler) AddFriend(c echo.Context) error {
	context := c.(CustomContext)
	currentUser := context.CurrentUser()
	if currentUser == nil || currentUser.Id != 1 {
		return FailRespWithMsg(c, Fail, "你没有权限添加友情链接")
	}

	var friend db.Friend
	if err := c.Bind(&friend); err != nil {
		return FailResp(c, ParamError)
	}

	if friend.Name == "" || friend.Url == "" || friend.Icon == "" {
		return FailRespWithMsg(c, Fail, "请输入必填项")
	}

	validUrl, _ := util.ValidHttpUrl(friend.Url)
	validIcon, _ := util.ValidHttpUrl(friend.Icon)
	if !validUrl || !validIcon {
		return FailRespWithMsg(c, Fail, "请检查地址格式")
	}

	if err := n.base.db.Create(&friend).Error; err != nil {
		n.base.log.Error().Msgf("保存友情链接失败, %v", err)
		return FailRespWithMsg(c, Fail, "添加友情链接失败")
	}

	return SuccessResp(c, h{})
}

// 删除友情链接
// @Router /api/friend/delete [post]
func (n FriendHandler) DeleteFriend(c echo.Context) error {
	context := c.(CustomContext)
	currentUser := context.CurrentUser()
	if currentUser == nil || currentUser.Id != 1 {
		return FailRespWithMsg(c, Fail, "你没有权限删除友情链接")
	}

	id, err := strconv.Atoi(c.QueryParam("id"))
	if err != nil {
		return FailResp(c, ParamError)
	}

	if err := n.base.db.Delete(&db.Friend{}, id).Error; err != nil {
		n.base.log.Error().Msgf("删除友情链接失败, %v", err)
		return FailRespWithMsg(c, Fail, "删除友情链接失败")
	}

	return SuccessResp(c, h{})
}
