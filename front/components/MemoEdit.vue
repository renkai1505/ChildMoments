<template>
  <div class="memo-edit-root">
    <div class="memo-edit-header">
      <NuxtLink class="flex items-center" title="返回主页">
        <UIcon @click="navigateTo('/')" name="i-carbon-chevron-left" class="w-6 h-6 cursor-pointer mr-4"/>
        <span v-if="$route.path==='/new'">新增内容</span>
        <span v-else>修改内容</span>
      </NuxtLink>
      <UButton class="memo-edit-pub-btn" @click="saveMemo">发表</UButton>
    </div>
    <div class="memo-edit-toolbar">
      <ExternalUrl v-model:favicon="state.externalFavicon" v-model:title="state.externalTitle"
                   v-model:url="state.externalUrl"/>
      <upload-image v-model:imgs="state.imgs" class="memo-edit-upload-btn"/>
      <music v-bind="state.music" @confirm="updateMusic"/>
      <upload-video @confirm="handleVideo" v-bind="state.video"/>
      <douban-edit v-model:type="doubanType" v-model:data="doubanData"/>
      <UPopover :popper="{ arrow: true }" mode="click">
        <UIcon name="i-carbon-calendar" class="w-7 h-7" title="自定义时间"/>
        <template #panel="{close}">
          <DatePicker
            v-model="state.createdAt"
            mode="datetime"
            is24hr
            :time-accuracy="2"
            :rules="{ seconds: 0 }"
            @close="close"
          />
        </template>
      </UPopover>
      <UIcon name="i-carbon-text-clear-format" @click="reset" class="w-7 h-7 cursor-pointer" title="清空"></UIcon>
    </div>

    <div class="memo-edit-content" @contextmenu.prevent="onContextMenu">
      <div class="relative">
        <UTextarea ref="contentRef" v-model="state.content" :rows="8" autoresize padded autofocus class="memo-edit-textarea"/>
        <UIcon class="text-[#9fc84a] w-7 h-7 animate-bounce absolute right-2 bottom-2 cursor-pointer select-none" name="i-carbon-face-satisfied" @click="toggleEmoji"/>
      </div>
      <Emoji v-if="emojiShow" @selected="emojiSelected" @close="emojiShow=false"/>
      <USelectMenu v-model="selectedLabel" :options="existTags" show-create-option-when="always"
                   multiple searchable creatable placeholder="选择标签" class="my-2 memo-edit-selectmenu" >
        <template #label>
          <span v-if="selectedLabel.length" class="truncate">{{ selectedLabel.join(',') }}</span>
          <span v-else>选择标签</span>
        </template>
      </USelectMenu>
      <UContextMenu v-model="isOpen" :virtual-element="virtualElement">
        <div class="px-2 py-1 flex flex-col gap-2 text-xs">
          <div class="mb-2 text-gray-300">点击标签插入</div>
          <div v-for="(tag,index) in existTags" :key="index" class="cursor-pointer">
            <UBadge size="xs" color="gray" variant="solid" @click="clickTag(tag)">{{ tag }}</UBadge>
          </div>
        </div>
      </UContextMenu>
    </div>

    <div class="memo-edit-footer">
      <div class="flex flex-row gap-2 items-center text-[#576b95] text-base cursor-pointer">
        <UPopover :popper="{ arrow: true }" mode="click">
          <div class="flex items-center gap-1">
            <UIcon name="i-carbon-location"/>
            <span>{{ state.location ? locationLabel : '自定义位置' }}</span>
          </div>
          <template #panel="{close}">
            <div class="p-4">
              <UButtonGroup>
                <UInput v-model="state.location" placeholder="自定义位置,空格分隔" class="memo-edit-location-input"/>
                <UButton @click="close" color="white" variant="solid">关闭</UButton>
              </UButtonGroup>
            </div>
          </template>
        </UPopover>
      </div>
      <div class="flex gap-2 text-gray-500 items-center">
        <span>{{ state.showType ? '公开' : '私密' }}</span>
        <UToggle v-model="state.showType"/>
      </div>
    </div>

    <div class="memo-edit-preview">
      <!-- 预览区 -->
      <div class="text-xs text-[#9DA4B0] mb-2">
        {{ state.createdAt ? dayjs(state.createdAt).format('YYYY-MM-DD HH:mm') : '' }}
        <span v-if="currentUser && currentUser.birthday && state.createdAt" class="ml-2 text-[#9fc84a]">
          ({{ getAgeString(currentUser.birthday, state.createdAt) }})
        </span>
      </div>
      <external-url-preview :favicon="state.externalFavicon" :title="state.externalTitle" :url="state.externalUrl"/>
      <upload-image-preview :imgs="state.imgs" @remove-image="handleRemoveImage" @drag-image="handleDragImage"/>
      <music-preview v-if="state.music && state.music.id && state.music.type && state.music.server"
                     v-bind="state.music"/>
      <douban-book-preview :book="doubanData" v-if="doubanType === 'book' && doubanData&& doubanData.title"/>
      <douban-movie-preview :movie="doubanData" v-if="doubanType === 'movie' && doubanData&& doubanData.title"/>
      <video-preview-iframe v-if="['bilibili', 'youtube'].includes(state.video.type) && state.video.value" :url="state.video.value"/>
      <video-preview v-if="state.video.type === 'online' && state.video.value" :url="state.video.value"/>
    </div>
  </div>
</template>

<script setup lang="ts">
import {useMouse, useWindowScroll} from '@vueuse/core'
import type {
  DoubanBook,
  DoubanMovie,
  ExtDTO,
  MemoVO,
  MetingMusicServer,
  MetingMusicType,
  MusicDTO,
  Video,
  VideoType
} from "~/types";
import { toast } from "vue-sonner";
import UploadImage from "~/components/UploadImage.vue";
import Emoji from "~/components/Emoji.vue";
import dayjs from "dayjs";
import { useState } from "#imports";
const currentUser = useState('userinfo');

function getAgeString(birthday: string | undefined, date: string): string {
  if (!birthday) return '';
  const birth = dayjs(birthday);
  const target = dayjs(date);
  if (!birth.isValid() || !target.isValid()) return '';
  let years = target.diff(birth, 'year');
  let months = target.diff(birth.add(years, 'year'), 'month');
  let days = target.diff(birth.add(years, 'year').add(months, 'month'), 'day');
  let result = '';
  if (years > 0) result += `${years}岁`;
  if (months > 0) result += `${months}个月`;
  if (days > 0) result += `${days}天`;
  return result || '0天';
}
import { useImageExifTime } from "~/utils";

const doubanType = ref<'book' | 'movie'>('book')
const doubanData = ref<DoubanBook | DoubanMovie>({})
const contentRef = ref(null)
const props = defineProps<{ id?: number }>()
const defaultState = {
  id: props.id || 0,
  createdAt: '' as string,
  content: "",
  ext: "",
  pinned: false,
  showType: true,
  location: "",
  externalFavicon: "",
  externalTitle: "",
  externalUrl: "",
  imgs: "",
  music: {
    id: '',
    api: 'https://api.i-meto.com/meting/api?server=:server&type=:type&id=:id&r=:r',
    server: 'netease' as MetingMusicServer,
    type: 'song' as MetingMusicType
  },
  video: {
    type: 'youtube' as VideoType,
    value: ""
  },
  doubanBook: {} as DoubanBook,
  doubanMovie: {} as DoubanMovie,
  tags: Array<string>(),
}
const selectedTags = ref<Array<string>>([])
const selectedLabel = computed({
  get:()=>selectedTags.value,
  set:(labels:Array<string>)=>{
    const tempLabels = Array<string>()
    labels.map(label=>{
      // @ts-ignore
      if(typeof  label !== 'string'){
        // @ts-ignore
        label = label.label
      }
      tempLabels.push(label)
      if(!existTags.value.includes(label)){
        existTags.value.push(label)
      }
    })
    selectedTags.value = [...tempLabels]
    console.log('selectedTags',selectedTags.value)
  }
})
const state = reactive({
  ...defaultState
})
const existTags = ref<string[]>([])
const reset = () => {
  Object.assign(state, defaultState)
}

const locationLabel = computed(() => {
  return state.location.split(" ").join(" · ")
})

const handleDragImage = (imgs: string[]) => {
  state.imgs = imgs.filter(Boolean).join(",")
}

const updateMusic = (music: MusicDTO) => {
  state.music.id = ""
  setTimeout(() => {
    Object.assign(state.music, music)
  }, 500)
}

const handleVideo = (video: Video) => {
  state.video = video
}

const {x, y} = useMouse()
const {y: windowY} = useWindowScroll()
const isOpen = ref(false)
const virtualElement = ref({getBoundingClientRect: () => ({})})
const handleRemoveImage = (img: string) => {
  state.imgs = state.imgs
    .split(",")
    .filter(item => item && item != img)
    .join(",")
}

function onContextMenu() {
  if (existTags.value.length <= 0) {
    return
  }
  const top = unref(y) - unref(windowY)
  const left = unref(x)

  virtualElement.value.getBoundingClientRect = () => ({
    width: 0,
    height: 0,
    top,
    left
  })

  isOpen.value = true
}

const loadTags = async () => {
  const res = await useMyFetch<{
    tags: string[]
  }>("/tag/list")
  existTags.value = res.tags || []
}

const emojiShow = ref(false)

const toggleEmoji = () => {
  emojiShow.value = !emojiShow.value
}
const emojiSelected = (emoji: string) => {
  state.content = state.content + emoji
}

const clickTag = (tag: string) => {
  isOpen.value = false;
  if (!selectedLabel.value.includes(tag)){
    if (selectedLabel.value) {
      selectedLabel.value = [...selectedLabel.value , tag]
    } else {
      selectedLabel.value = [tag]
    }
  }

  //@ts-ignore
  (contentRef.value?.textarea as HTMLTextAreaElement).focus()
}

// 监听图片上传，如果有EXIF时间，则自动设置为发布时间
const imageExifTime = useImageExifTime()
watch(imageExifTime, (newExifTime) => {
  if (newExifTime && !state.id) { // 只在新建时使用EXIF时间
    state.createdAt = dayjs(newExifTime).format()
    toast.success("已使用照片的拍摄时间作为发布时间")
  }
})

// 监听图片变化
watch(() => state.imgs, (newImgs) => {
  // 如果从无图片变为有图片，且有EXIF时间，则设置发布时间
  const hasImages = newImgs && newImgs.split(',').filter(Boolean).length > 0
  if (hasImages && imageExifTime.value && !state.id) {
    state.createdAt = dayjs(imageExifTime.value).format()
  }
  // 如果有图片但没有EXIF时间，且未设置过createdAt，则提示用户手动选择
  if (hasImages && !imageExifTime.value && !state.createdAt && !state.id) {
    toast.info("未检测到照片时间，请手动选择发布时间")
  }
}, { immediate: true })

onMounted(async () => {
  if (state.id > 0) {
    const res = await useMyFetch<MemoVO>('/memo/get?id=' + state.id)
    Object.assign(state, res)
    state.showType = res.showType === 1
    const ext = JSON.parse(res.ext) as ExtDTO
    Object.assign(state.music, ext.music)
    Object.assign(state.video, ext.video)
    doubanType.value = ext.doubanBook && ext.doubanBook.title ? 'book' : 'movie'
    doubanData.value = doubanType.value === 'book' ? ext.doubanBook : ext.doubanMovie
    selectedLabel.value = res.tags ? res.tags.substring(0,res.tags.length-1).split(',') : []
    state.createdAt = dayjs(res.createdAt).format()
  }
  await loadTags()
})

// const keydown=(event:KeyboardEvent)=>{
//   if(event.key === '#'){
//     tagPopoverOpen.value = true
//   }
// }

const saveMemo = async () => {

  const doubanKey = doubanType.value === 'book' ? 'doubanBook' : 'doubanMovie'
  await useMyFetch('/memo/save', {
    id: state.id,
    content: state.content,
    ext: {
      music: state.music.id ? state.music : {},
      [doubanKey]: doubanData.value,
      video: state.video.value ? state.video : {},
    },
    pinned: state.pinned,
    showType: state.showType ? 1 : 0,
    externalFavicon: state.externalUrl ? state.externalFavicon : "",
    externalTitle: state.externalTitle,
    externalUrl: state.externalUrl,
    imgs: state.imgs.split(",").filter(Boolean),
    location: state.location,
    tags: selectedLabel.value,
    createdAt: state.createdAt || dayjs().format(),
  })
  toast.success("保存成功!")
  await navigateTo('/')
}

</script>

<style scoped>
.memo-edit-root {
  max-width: 600px;
  margin: 0 auto;
  background: #fff;
  border-radius: 12px;
  box-shadow: 0 2px 8px rgba(0,0,0,0.04);
  padding: 0.5rem 0.5rem 5rem 0.5rem;
  min-height: 100vh;
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}
@media (max-width: 600px) {
  .memo-edit-root {
    border-radius: 0;
    box-shadow: none;
    padding: 0.5rem 0.2rem 5rem 0.2rem;
    min-height: 100vh;
  }
}
.memo-edit-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0.5rem 0;
  font-size: 1.1rem;
  font-weight: 600;
}
.memo-edit-pub-btn {
  font-size: 1.1rem;
  padding: 0.5rem 1.2rem;
  border-radius: 8px;
}
.memo-edit-toolbar {
  display: flex;
  flex-wrap: wrap;
  gap: 0.7rem;
  align-items: center;
  padding-bottom: 0.2rem;
  font-size: 1.1rem;
}
.memo-edit-upload-btn {
  border: 2px dashed #9fc84a;
  border-radius: 8px;
  padding: 0.2rem 0.5rem;
  background: #f8fff0;
}
.memo-edit-content {
  margin-top: 0.5rem;
  background: #f9f9f9;
  border-radius: 8px;
  padding: 0.7rem 0.5rem 0.5rem 0.5rem;
  min-height: 120px;
  font-size: 1.1rem;
}
.memo-edit-textarea {
  font-size: 1.1rem;
  min-height: 120px;
  border-radius: 8px;
  padding: 0.7rem 0.5rem;
}
.memo-edit-selectmenu {
  font-size: 1.1rem;
  min-height: 2.5rem;
}
.memo-edit-footer {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0.5rem 0;
  font-size: 1rem;
}
.memo-edit-location-input {
  font-size: 1.1rem;
  min-width: 120px;
}
.memo-edit-preview {
  margin-top: 0.5rem;
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}
@media (max-width: 600px) {
  .memo-edit-header, .memo-edit-footer, .memo-edit-toolbar {
    font-size: 1rem;
    gap: 0.4rem;
  }
  .memo-edit-pub-btn {
    font-size: 1rem;
    padding: 0.4rem 1rem;
  }
  .memo-edit-content, .memo-edit-textarea {
    font-size: 1rem;
    padding: 0.5rem 0.3rem;
  }
  .memo-edit-selectmenu {
    font-size: 1rem;
    min-height: 2.2rem;
  }
}
</style>