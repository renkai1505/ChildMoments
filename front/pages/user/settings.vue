<template>
  <Header :user="currentUser"/>

  <div class="space-y-4  flex flex-col p-4 my-4 dark:bg-neutral-800">
    <UFormGroup label="头像" name="avatarUrl" :ui="{label:{base:'font-bold'}}">
      <UInput type="file" size="sm" icon="i-heroicons-folder" @change="uploadAvatarUrl"/>
      <div class="text-gray-500 text-sm my-2">或者输入在线地址</div>
      <UInput v-model="state.avatarUrl" class="mb-2"/>
      <UAvatar :src="state.avatarUrl" size="lg"/>
    </UFormGroup>
    <UFormGroup label="顶部图片" name="coverUrl" :ui="{label:{base:'font-bold'}}">
      <UInput type="file" size="sm" icon="i-heroicons-folder" @change="uploadCoverUrl"/>
      <div class="text-gray-500 text-sm my-2">或者输入在线地址</div>
      <UInput v-model="state.coverUrl" class="mb-2"/>
      <img :src="state.coverUrl" class="w-full rounded object-cover" alt="" />
    </UFormGroup>
    <UFormGroup label="登录名" name="username" :ui="{label:{base:'font-bold'}}">
      <UInput v-model="state.username" disabled />
    </UFormGroup>
    <UFormGroup label="昵称" name="nickname" :ui="{label:{base:'font-bold'}}">
      <UInput v-model="state.nickname"/>
    </UFormGroup>
    <UFormGroup label="心情状态" name="slogan" :ui="{label:{base:'font-bold'}}">
      <UInput v-model="state.slogan"/>
    </UFormGroup>
    <UFormGroup label="密码" name="slogan" :ui="{label:{base:'font-bold'}}">
      <UInput v-model="state.password" type="password" placeholder="留空则不修改密码"/>
    </UFormGroup>
    <UFormGroup label="邮箱" name="email" :ui="{label:{base:'font-bold'}}">
      <UInput v-model="state.email" type="email" placeholder="若管理员启用了邮件通知，将在收到评论时发送邮件通知"/>
    </UFormGroup>
    <UFormGroup label="生日" name="birthday" :ui="{label:{base:'font-bold'}}">
      <UInput v-model="state.birthday" type="date"/>
    </UFormGroup>
    <UButton class="justify-center" @click="save">保存</UButton>
  </div>
</template>

<script setup lang="ts">
import type {UserVO} from "~/types";
import {toast} from "vue-sonner";
import {useUpload} from "~/utils";
import {useGlobalState} from "~/store";
const global = useGlobalState()
const currentUser = useState<UserVO>('userinfo')
const state = reactive({
  password: "",
  username: "",
  nickname: "",
  slogan: "",
  avatarUrl: "",
  coverUrl: "",
  email: "",
  css: "",
  js: "",
  birthday: ""
})
const logout = async () => {
  global.value.userinfo = {}
  await navigateTo('/')
}
const reload = async () => {
  const res = await useMyFetch<UserVO>('/user/profile')
  if (res) {
    if (res.birthday) res.birthday = res.birthday.slice(0, 10)
    Object.assign(state, res)
    currentUser.value = res
  }
}

const save = async () => {
  await useMyFetch('/user/saveProfile', state)
  toast.success("保存成功")
  const res = await useMyFetch<UserVO>('/user/profile')
  if (res) {
    if (res.birthday) res.birthday = res.birthday.slice(0, 10)
    Object.assign(state, res)
    currentUser.value = res
  }
}

const uploadAvatarUrl = async (files: FileList) => {
  for (let i = 0; i < files.length; i++) {
    if (files[i].type.indexOf("image") < 0){
      toast.error("只能上传图片");
      return
    }
  }
  const result = await useUpload(files)
  if (result.length) {
    toast.success("上传成功")
    state.avatarUrl = result[0]
  }
}

const uploadCoverUrl = async (files: FileList) => {
  for (let i = 0; i < files.length; i++) {
    if (files[i].type.indexOf("image") < 0){
      toast.error("只能上传图片");
      return
    }
  }
  const result = await useUpload(files)
  if (result.length) {
    toast.success("上传成功")
    state.coverUrl = result[0]
  }
}

onMounted(async () => {
  Object.assign(state,currentUser.value)
})

</script>

<style scoped>

</style>