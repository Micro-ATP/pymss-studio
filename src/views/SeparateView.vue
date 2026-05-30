<script setup lang="ts">
import { computed, onMounted, onBeforeUnmount, ref, watch } from 'vue'
import { storeToRefs } from 'pinia'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import { useMessage } from 'naive-ui'
import { getCurrentWebview } from '@tauri-apps/api/webview'
import type { UnlistenFn } from '@tauri-apps/api/event'
import {
  DocumentTextOutline,
  CubeOutline,
  FolderOpenOutline,
  PlayOutline,
  MusicalNotesOutline,
  FolderOutline,
  CloudUploadOutline,
  CloseOutline,
  ArrowBackOutline,
  ArrowForwardOutline,
} from '@vicons/ionicons5'
import { useModelStore } from '@/stores/model'
import { useTaskStore } from '@/stores/task'
import { useSettingsStore } from '@/stores/settings'
import { useAppStore } from '@/stores/app'

const { t } = useI18n()
const message = useMessage()
const router = useRouter()
const task = useTaskStore()
const model = useModelStore()
const settings = useSettingsStore()
const app = useAppStore()

const {
  inputFiles,
  useTta,
  debug,
  batchSize,
  overlapSize,
  chunkSize,
  normalize,
  maskMode,
  useAmp,
  cudaAttentionBackend,
  fuseConvBn,
  useChannelsLast,
  shifts,
  split,
  overlap,
} = storeToRefs(task)
const { selectedModel, downloadedModels, isLoading } = storeToRefs(model)

const isDragging = ref(false)
const modelsAutoLoaded = ref(false)
const currentStep = ref(0)
let unlistenDragDrop: UnlistenFn | null = null

const formatOptions = [
  { label: 'WAV', value: 'wav' },
  { label: 'FLAC', value: 'flac' },
  { label: 'MP3', value: 'mp3' },
  { label: 'M4A', value: 'm4a' },
]

const wavBitDepthOptions = computed(() => [
  { label: t('audio.pcm16'), value: 'PCM_16' },
  { label: t('audio.pcm24'), value: 'PCM_24' },
  { label: t('audio.float'), value: 'FLOAT' },
])
const flacBitDepthOptions = computed(() => [
  { label: t('audio.pcm16'), value: 'PCM_16' },
  { label: t('audio.pcm24'), value: 'PCM_24' },
])
const bitRateOptions = computed(() => [
  { label: t('audio.bitrate128'), value: '128k' },
  { label: t('audio.bitrate192'), value: '192k' },
  { label: t('audio.bitrate256'), value: '256k' },
  { label: t('audio.bitrate320'), value: '320k' },
])
const m4aCodecOptions = computed(() => [
  { label: t('audio.codecAacAt'), value: 'aac_at' },
  { label: t('audio.codecAac'), value: 'aac' },
  { label: t('audio.codecAlac'), value: 'alac' },
])

const selectedModelName = computed(() => String(selectedModel.value || ''))
const selectedModelInfo = computed(() => downloadedModels.value.find(item => item.name === selectedModelName.value) || null)
const modelOptions = computed(() => downloadedModels.value.map(item => ({ label: item.name, value: item.name })))
const modelDownloaded = computed(() => Boolean(selectedModelName.value) && downloadedModels.value.some(item => item.name === selectedModelName.value))
const selectedModelCategory = computed(() => selectedModelInfo.value?.categoryCn || selectedModelInfo.value?.category || t('common.notSet'))
const selectedModelTarget = computed(() => selectedModelInfo.value?.targetStem || selectedModelInfo.value?.configTargetInstrument || t('common.notSet'))
const selectedModelArchitecture = computed(() => selectedModelInfo.value?.architecture || selectedModelInfo.value?.modelType || t('common.notSet'))

const normalizedOutputDir = computed(() => (settings.outputDir || 'results').trim() || 'results')
const outputPreview = computed(() => {
  const base = normalizedOutputDir.value.replace(/[\\/]$/, '')
  const separator = base.includes('\\') ? '\\' : '/'
  return settings.separateTaskOutputDir ? `${base}${separator}sep_${t('separate.taskIdPreview')}` : base
})
const formatLabel = computed(() => String(settings.defaultFormat || 'wav').toUpperCase())

function getFileName(path: string) {
  return path.split(/[/\\]/).filter(Boolean).pop() || path
}

const steps = computed(() => [
  { key: 'input', label: t('separate.stepInput'), desc: t('separate.stepInputDesc'), icon: DocumentTextOutline, done: inputFiles.value.length > 0 },
  { key: 'model', label: t('separate.stepModel'), desc: t('separate.stepModelDesc'), icon: CubeOutline, done: modelDownloaded.value },
  { key: 'output', label: t('separate.stepOutput'), desc: t('separate.stepOutputDesc'), icon: FolderOpenOutline, done: Boolean(normalizedOutputDir.value) },
])

const canLeaveInput = computed(() => inputFiles.value.length > 0)
const canLeaveModel = computed(() => modelDownloaded.value)
const canGoNext = computed(() => {
  if (currentStep.value === 0) return canLeaveInput.value
  if (currentStep.value === 1) return canLeaveModel.value
  return true
})
const canStart = computed(() => inputFiles.value.length > 0 && modelDownloaded.value)

// 自动修正“幽灵选择”：当所选模型不在已下载列表中时，回退到第一个已下载模型。
// 解决从缓存加载后 selectedModel 停留在默认值、误显示“模型未安装”的问题。
watch(
  [downloadedModels, selectedModel, isLoading],
  ([list, current, loading]) => {
    if (loading) return
    if (!list.length) return
    const valid = current && list.some((item) => item.name === current)
    if (!valid) {
      selectedModel.value = list[0].name
    }
  },
  { immediate: true },
)

onMounted(async () => {
  if (!app.envInfo && !app.envLoading) {
    app.checkEnvInBackground().catch(() => {})
  }
  if (!downloadedModels.value.length && !modelsAutoLoaded.value && !isLoading.value) {
    modelsAutoLoaded.value = true
    model.loadModels().catch(() => {})
  }
  try {
    unlistenDragDrop = await getCurrentWebview().onDragDropEvent(async (event) => {
      const type = event.payload.type
      if (type === 'over' || type === 'enter') {
        isDragging.value = true
      } else if (type === 'drop') {
        isDragging.value = false
        const paths = (event.payload as { paths?: string[] }).paths || []
        const added = await task.addPaths(paths)
        if (added > 0) message.success(t('separate.addedFiles', { count: added }))
        else message.warning(t('separate.noAudioAdded'))
      } else {
        isDragging.value = false
      }
    })
  } catch {
    // 非 Tauri 环境静默降级
  }
})

onBeforeUnmount(() => {
  if (unlistenDragDrop) unlistenDragDrop()
})

async function handlePickFiles() {
  const before = inputFiles.value.length
  await task.pickFiles()
  const added = inputFiles.value.length - before
  if (added > 0) message.success(t('separate.addedFiles', { count: added }))
}

async function handlePickFolder() {
  const count = await task.pickInputFolder()
  if (count > 0) message.success(t('separate.folderScanned', { count }))
  else message.warning(t('separate.folderEmpty'))
}

function goNext() {
  if (currentStep.value < 2 && canGoNext.value) currentStep.value += 1
}

function goBack() {
  if (currentStep.value > 0) currentStep.value -= 1
}

function gotoStep(index: number) {
  // 仅允许跳到已满足前置条件的步骤
  if (index <= currentStep.value) {
    currentStep.value = index
    return
  }
  if (index >= 1 && !canLeaveInput.value) return
  if (index >= 2 && !canLeaveModel.value) return
  currentStep.value = index
}

async function start() {
  if (!inputFiles.value.length) {
    message.warning(t('separate.startHintNoInput'))
    currentStep.value = 0
    return
  }
  if (!modelDownloaded.value) {
    message.warning(t('separate.startHintModelMissing'))
    currentStep.value = 1
    return
  }
  try {
    const result = await task.startSeparation()
    if (result && result.failed > 0) {
      message.warning(t('separate.batchPartial', { succeeded: result.succeeded, failed: result.failed }))
    } else {
      message.success(t('separate.batchStarted', { count: result?.succeeded ?? 1 }))
    }
    task.clearInputFiles()
    currentStep.value = 0
    router.push('/tasks')
  } catch (err) {
    message.error(err instanceof Error ? err.message : t('toast.taskFailed'))
  }
}
</script>

<template>
  <div class="page separate-page">
    <div class="page-header-compact separate-header">
      <div>
        <h1>{{ t('separate.title') }}</h1>
        <p>{{ t('separate.subtitle') }}</p>
      </div>
    </div>

    <!-- 步骤指示器 -->
    <div class="stepper" role="tablist">
      <button
        v-for="(step, index) in steps"
        :key="step.key"
        type="button"
        class="stepper__item"
        :class="{
          'stepper__item--active': currentStep === index,
          'stepper__item--done': step.done && currentStep !== index,
        }"
        @click="gotoStep(index)"
      >
        <span class="stepper__index">
          <n-icon :component="step.icon" />
        </span>
        <span class="stepper__copy">
          <strong>{{ index + 1 }}. {{ step.label }}</strong>
          <small>{{ step.desc }}</small>
        </span>
      </button>
    </div>

    <div class="wizard-body">
      <!-- 步骤 1：输入来源 -->
      <section v-show="currentStep === 0" class="config-panel">
        <div class="panel-heading">
          <div class="panel-heading__icon"><n-icon :component="DocumentTextOutline" /></div>
          <div>
            <h2>{{ t('separate.input') }}</h2>
            <p>{{ t('separate.inputPanelHint') }}</p>
          </div>
        </div>

        <div class="button-row">
          <n-button secondary @click="handlePickFiles">
            <template #icon><n-icon :component="MusicalNotesOutline" /></template>
            {{ t('separate.chooseFiles') }}
          </n-button>
          <n-button secondary @click="handlePickFolder">
            <template #icon><n-icon :component="FolderOutline" /></template>
            {{ t('separate.chooseFolder') }}
          </n-button>
        </div>

        <!-- 候选歌曲列表（同时作为拖拽目标） -->
        <div class="candidate" :class="{ 'candidate--dragging': isDragging }">
          <div class="candidate__head">
            <strong>{{ t('separate.candidateTitle') }}</strong>
            <span>{{ t('separate.candidateCount', { count: inputFiles.length }) }}</span>
            <n-button
              v-if="inputFiles.length"
              text
              size="small"
              type="error"
              @click="task.clearInputFiles()"
            >
              {{ t('separate.clearAll') }}
            </n-button>
          </div>
          <div v-if="inputFiles.length" class="candidate__list">
            <div v-for="path in inputFiles" :key="path" class="candidate__item">
              <n-icon :component="MusicalNotesOutline" class="candidate__item-icon" />
              <div class="candidate__item-main">
                <strong>{{ getFileName(path) }}</strong>
                <code>{{ path }}</code>
              </div>
              <n-button quaternary circle size="tiny" @click="task.removeInputFile(path)">
                <template #icon><n-icon :component="CloseOutline" /></template>
              </n-button>
            </div>
          </div>
          <div v-else class="candidate__empty">
            <div class="candidate__empty-icon"><n-icon :component="CloudUploadOutline" /></div>
            <span>{{ isDragging ? t('separate.dropHere') : t('separate.candidateEmpty') }}</span>
          </div>
        </div>
      </section>

      <!-- 步骤 2：分离模型 -->
      <section v-show="currentStep === 1" class="config-panel">
        <div class="panel-heading">
          <div class="panel-heading__icon"><n-icon :component="CubeOutline" /></div>
          <div>
            <h2>{{ t('separate.model') }}</h2>
            <p>{{ t('separate.modelPanelHint') }}</p>
          </div>
        </div>

        <n-select
          v-model:value="selectedModel"
          :placeholder="isLoading ? t('separate.loadingModels') : t('separate.noDownloadedModels')"
          :options="modelOptions"
          :loading="isLoading"
          filterable
          clearable
        />

        <div v-if="selectedModelInfo" class="model-info-card">
          <div class="model-info-card__head">
            <strong>{{ selectedModelInfo.name }}</strong>
            <span>{{ selectedModelArchitecture }}</span>
          </div>
          <div class="model-info-card__grid">
            <div>
              <span>{{ t('separate.modelInfoCategory') }}</span>
              <strong>{{ selectedModelCategory }}</strong>
            </div>
            <div>
              <span>{{ t('separate.modelInfoTargetStem') }}</span>
              <strong>{{ selectedModelTarget }}</strong>
            </div>
            <div>
              <span>{{ t('separate.modelInfoArchitecture') }}</span>
              <strong>{{ selectedModelArchitecture }}</strong>
            </div>
            <div v-if="selectedModelInfo.configInstruments">
              <span>{{ t('separate.modelInfoInstruments') }}</span>
              <strong>{{ selectedModelInfo.configInstruments }}</strong>
            </div>
          </div>
          <p v-if="selectedModelInfo.classificationBasis" class="model-info-card__desc">
            {{ selectedModelInfo.classificationBasis }}
          </p>
        </div>
        <div v-else-if="selectedModelName && !modelDownloaded" class="model-info-card model-info-card--warn">
          {{ t('separate.startHintModelMissing') }}
        </div>
        <div v-else-if="!downloadedModels.length && !isLoading" class="model-empty-hint">
          {{ t('separate.modelEmptyHint') }}
        </div>

        <div class="button-row">
          <n-button v-if="!downloadedModels.length" secondary :loading="isLoading" @click="model.loadModels()">
            {{ t('separate.modelEmptyAction') }}
          </n-button>
          <n-button secondary @click="router.push('/models')">
            {{ t('separate.manageModels') }}
          </n-button>
        </div>
      </section>

      <!-- 步骤 3：输出设置 + 运行参数 -->
      <section v-show="currentStep === 2" class="config-panel">
        <div class="panel-heading">
          <div class="panel-heading__icon"><n-icon :component="FolderOpenOutline" /></div>
          <div>
            <h2>{{ t('separate.output') }}</h2>
            <p>{{ t('separate.outputPanelHint') }}</p>
          </div>
        </div>

        <!-- 输出位置 -->
        <div class="settings-group">
          <div class="settings-group__head">
            <strong>{{ t('separate.outputLocationTitle') }}</strong>
            <span>{{ t('separate.outputLocationHint') }}</span>
          </div>

          <div class="output-grid">
            <div class="field-block field-block--wide">
              <label>{{ t('settings.outputDir') }}</label>
              <n-input v-model:value="settings.outputDir" :placeholder="t('separate.outputDefault')" clearable />
            </div>
            <div class="field-block">
              <label>{{ t('settings.defaultFormat') }}</label>
              <n-select v-model:value="settings.defaultFormat" :options="formatOptions" />
            </div>
          </div>

          <div class="button-row">
            <n-button secondary @click="settings.pickOutputDir()">
              {{ t('separate.chooseOutput') }}
            </n-button>
            <n-button secondary @click="task.revealPath(normalizedOutputDir)">
              {{ t('separate.openOutput') }}
            </n-button>
          </div>

          <div class="settings-row">
            <div class="settings-row__copy">
              <strong>{{ t('separate.separateTaskOutputDir') }}</strong>
              <span>{{ t('separate.separateTaskOutputDirHint') }}</span>
            </div>
            <n-switch v-model:value="settings.separateTaskOutputDir" />
          </div>

          <div class="output-preview">
            <span>{{ t('separate.outputPreview') }}</span>
            <code>{{ outputPreview }}</code>
          </div>
        </div>

        <!-- 运行选项 -->
        <div class="settings-group">
          <div class="settings-group__head">
            <strong>{{ t('separate.runOptionsTitle') }}</strong>
            <span>{{ t('separate.runOptionsHint') }}</span>
          </div>
          <div class="check-list">
            <n-checkbox v-model:checked="useTta">{{ t('separate.tta') }}</n-checkbox>
            <n-checkbox v-model:checked="debug">{{ t('separate.debug') }}</n-checkbox>
          </div>
        </div>
        <!-- 音频质量（可修改） -->
        <div class="settings-group">
          <div class="settings-group__head">
            <strong>{{ t('separate.audioQualityTitle') }} · {{ formatLabel }}</strong>
            <span>{{ t('separate.audioQualityEditable') }}</span>
          </div>
          <n-grid :cols="2" :x-gap="16" :y-gap="16" responsive="screen">
            <n-grid-item v-if="settings.defaultFormat === 'wav'">
              <div class="field-block">
                <label>{{ t('audio.wavBitDepth') }}</label>
                <n-select v-model:value="settings.wavBitDepth" :options="wavBitDepthOptions" />
              </div>
            </n-grid-item>
            <n-grid-item v-if="settings.defaultFormat === 'flac'">
              <div class="field-block">
                <label>{{ t('audio.flacBitDepth') }}</label>
                <n-select v-model:value="settings.flacBitDepth" :options="flacBitDepthOptions" />
              </div>
            </n-grid-item>
            <n-grid-item v-if="settings.defaultFormat === 'mp3'">
              <div class="field-block">
                <label>{{ t('audio.mp3BitRate') }}</label>
                <n-select v-model:value="settings.mp3BitRate" :options="bitRateOptions" />
              </div>
            </n-grid-item>
            <n-grid-item v-if="settings.defaultFormat === 'm4a'">
              <div class="field-block">
                <label>{{ t('audio.m4aBitRate') }}</label>
                <n-select v-model:value="settings.m4aBitRate" :options="bitRateOptions" />
              </div>
            </n-grid-item>
            <n-grid-item v-if="settings.defaultFormat === 'm4a'">
              <div class="field-block">
                <label>{{ t('audio.m4aCodec') }}</label>
                <n-select v-model:value="settings.m4aCodec" :options="m4aCodecOptions" />
              </div>
            </n-grid-item>
          </n-grid>
        </div>

        <!-- 高级推理参数 -->
        <n-collapse :default-expanded-names="[]">
          <n-collapse-item :title="t('inference.advancedParams')" name="inference">
            <p class="advanced-hint">{{ t('separate.advancedPanelHint') }}</p>
            <n-grid :cols="2" :x-gap="16" :y-gap="16" responsive="screen">
              <n-grid-item>
                <div class="field-block">
                  <label>{{ t('inference.batchSize') }}</label>
                  <n-input-number v-model:value="batchSize" :min="1" :max="32" style="width:100%" />
                </div>
              </n-grid-item>
              <n-grid-item>
                <div class="field-block">
                  <label>{{ t('inference.overlapSize') }}</label>
                  <n-input-number v-model:value="overlapSize" :min="0" :max="128" style="width:100%" />
                </div>
              </n-grid-item>
              <n-grid-item>
                <div class="field-block">
                  <label>{{ t('inference.chunkSize') }}</label>
                  <n-input-number v-model:value="chunkSize" :min="0" :max="1048576" :step="1024" style="width:100%" />
                </div>
              </n-grid-item>
              <n-grid-item>
                <div class="field-block">
                  <label>{{ t('inference.shifts') }}</label>
                  <n-input-number v-model:value="shifts" :min="0" :max="16" style="width:100%" />
                </div>
              </n-grid-item>
              <n-grid-item>
                <div class="field-block">
                  <label>{{ t('inference.overlap') }}</label>
                  <n-input-number v-model:value="overlap" :min="0" :max="1" :step="0.05" style="width:100%" />
                </div>
              </n-grid-item>
              <n-grid-item>
                <div class="field-block">
                  <label>{{ t('inference.maskMode') }}</label>
                  <n-select
                    v-model:value="maskMode"
                    :placeholder="t('common.default')"
                    clearable
                    :options="[
                      { label: t('inference.maskNone'), value: 'none' },
                      { label: t('inference.maskClamp'), value: 'clamp' },
                      { label: t('inference.maskGauss'), value: 'gauss' },
                      { label: t('inference.maskSoft'), value: 'soft' },
                    ]"
                  />
                </div>
              </n-grid-item>
            </n-grid>
            <div class="check-list check-list--spaced">
              <n-checkbox v-model:checked="normalize">{{ t('inference.normalize') }}</n-checkbox>
              <n-checkbox v-model:checked="split">{{ t('inference.split') }}</n-checkbox>
              <n-checkbox v-model:checked="useAmp">{{ t('inference.useAmp') }}</n-checkbox>
              <n-checkbox v-model:checked="fuseConvBn">{{ t('inference.fuseConvBn') }}</n-checkbox>
              <n-checkbox v-model:checked="useChannelsLast">{{ t('inference.useChannelsLast') }}</n-checkbox>
            </div>
          </n-collapse-item>
        </n-collapse>
      </section>
    </div>

    <!-- 底部导航 -->
    <div class="wizard-footer">
      <n-button v-if="currentStep > 0" secondary size="large" @click="goBack">
        <template #icon><n-icon :component="ArrowBackOutline" /></template>
        {{ t('separate.back') }}
      </n-button>
      <div class="wizard-footer__spacer" />
      <n-button
        v-if="currentStep < 2"
        type="primary"
        size="large"
        :disabled="!canGoNext"
        @click="goNext"
      >
        {{ t('separate.next') }}
        <template #icon><n-icon :component="ArrowForwardOutline" /></template>
      </n-button>
      <n-button
        v-else
        type="primary"
        size="large"
        :disabled="!canStart"
        @click="start"
      >
        <template #icon><n-icon :component="PlayOutline" /></template>
        {{ t('separate.startTask') }}
      </n-button>
    </div>
  </div>
</template>

<style scoped>
.separate-page {
  display: grid;
  gap: 16px;
}

.separate-header {
  margin-bottom: 0;
}

/* 步骤指示器 */
.stepper {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 8px;
  padding: 8px;
  border: 1px solid var(--outline);
  border-radius: 18px;
  background: color-mix(in srgb, var(--surface-1) 76%, transparent);
}

.stepper__item {
  min-width: 0;
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 11px 12px;
  border: none;
  border-radius: 14px;
  background: transparent;
  color: var(--on-surface-muted);
  cursor: pointer;
  text-align: left;
  transition: background 140ms ease, color 140ms ease;
}

.stepper__item:hover {
  background: var(--surface-2);
}

.stepper__item--active {
  background: var(--primary-soft);
  color: var(--primary-strong);
}
.stepper__item--done {
  color: var(--primary-strong);
}

.stepper__index {
  width: 34px;
  height: 34px;
  display: grid;
  place-items: center;
  flex: 0 0 auto;
  border-radius: 10px;
  font-size: 18px;
  color: var(--on-surface-muted);
  background: var(--surface-2);
}

.stepper__item--active .stepper__index,
.stepper__item--done .stepper__index {
  color: #fff;
  background: var(--primary);
}

.stepper__copy {
  min-width: 0;
  display: grid;
  gap: 2px;
}

.stepper__copy strong {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 13px;
}

.stepper__copy small {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 11px;
  color: var(--on-surface-muted);
}
.wizard-body {
  display: grid;
}

.config-panel {
  display: grid;
  gap: 14px;
  padding: 20px;
  border: 1px solid var(--outline);
  border-radius: 18px;
  background: var(--surface-1);
}

.panel-heading {
  display: flex;
  align-items: flex-start;
  gap: 12px;
}

.panel-heading__icon {
  width: 38px;
  height: 38px;
  display: grid;
  place-items: center;
  flex: 0 0 auto;
  border-radius: 12px;
  font-size: 19px;
  color: var(--primary-strong);
  background: var(--primary-soft);
}

.panel-heading h2 {
  margin: 0;
  font-size: 16px;
  letter-spacing: -0.02em;
}

.panel-heading p {
  margin: 4px 0 0;
  color: var(--on-surface-muted);
  font-size: 12px;
  line-height: 1.5;
}
.button-row {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
}
.candidate {
  display: grid;
  gap: 10px;
  padding: 14px;
  border: 1px solid var(--outline);
  border-radius: 16px;
  background: color-mix(in srgb, var(--surface-2) 62%, transparent);
  transition: border-color 140ms ease, background 140ms ease;
}

.candidate--dragging {
  border-color: var(--primary);
  border-style: dashed;
  background: var(--primary-soft);
}

.candidate__head {
  display: flex;
  align-items: center;
  gap: 10px;
}

.candidate__head strong {
  font-size: 13px;
}

.candidate__head span {
  flex: 1;
  color: var(--on-surface-muted);
  font-size: 12px;
}

.candidate__list {
  display: grid;
  gap: 8px;
  max-height: 320px;
  overflow-y: auto;
}

.candidate__item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 9px 11px;
  border: 1px solid var(--outline);
  border-radius: 12px;
  background: var(--surface-1);
}

.candidate__item-icon {
  flex: 0 0 auto;
  font-size: 16px;
  color: var(--primary-strong);
}

.candidate__item-main {
  min-width: 0;
  flex: 1;
  display: grid;
  gap: 2px;
}
.candidate__item-main strong {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 13px;
}

.candidate__item-main code {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: var(--on-surface-muted);
  font-size: 11px;
}

.candidate__empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 10px;
  padding: 32px 16px;
  text-align: center;
  color: var(--on-surface-muted);
  font-size: 12px;
  line-height: 1.6;
}

.candidate__empty-icon {
  width: 48px;
  height: 48px;
  display: grid;
  place-items: center;
  border-radius: 14px;
  font-size: 24px;
  color: var(--primary-strong);
  background: var(--primary-soft);
}
.model-info-card {
  display: grid;
  gap: 12px;
  padding: 14px;
  border: 1px solid var(--outline);
  border-radius: 16px;
  background: color-mix(in srgb, var(--surface-2) 62%, transparent);
}

.model-info-card--warn {
  color: var(--warning);
  border-color: var(--warning);
  background: color-mix(in srgb, var(--warning) 12%, var(--surface-2));
  font-size: 12px;
  line-height: 1.5;
}

.model-info-card__head {
  min-width: 0;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.model-info-card__head strong {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 14px;
}

.model-info-card__head span {
  flex: 0 0 auto;
  padding: 3px 8px;
  border-radius: 999px;
  color: var(--primary-strong);
  background: var(--primary-soft);
  font-size: 11px;
}

.model-info-card__grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 10px 14px;
}

.model-info-card__grid div {
  min-width: 0;
  display: grid;
  gap: 3px;
}

.model-info-card__grid span {
  color: var(--on-surface-muted);
  font-size: 11px;
}

.model-info-card__grid strong {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 12px;
}

.model-info-card__desc {
  margin: 0;
  color: var(--on-surface-muted);
  font-size: 12px;
  line-height: 1.6;
}

.model-empty-hint {
  color: var(--on-surface-muted);
  font-size: 12px;
  line-height: 1.5;
}
.field-block {
  display: grid;
  gap: 6px;
}

.field-block label {
  font-size: 12px;
  color: var(--on-surface-muted);
}

.output-grid {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 180px;
  gap: 12px;
}

/* 统一分区卡片 */
.settings-group {
  display: grid;
  gap: 14px;
  padding: 16px;
  border: 1px solid var(--outline);
  border-radius: 16px;
  background: color-mix(in srgb, var(--surface-2) 62%, transparent);
}

.settings-group__head {
  display: grid;
  gap: 3px;
}

.settings-group__head strong {
  font-size: 13px;
}

.settings-group__head span {
  color: var(--on-surface-muted);
  font-size: 12px;
  line-height: 1.5;
}

/* 分区内的开关行 */
.settings-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 12px 14px;
  border: 1px solid var(--outline);
  border-radius: 12px;
  background: var(--surface-1);
}

.settings-row__copy {
  min-width: 0;
  display: grid;
  gap: 3px;
}

.settings-row__copy strong {
  font-size: 13px;
}

.settings-row__copy span {
  color: var(--on-surface-muted);
  font-size: 12px;
  line-height: 1.5;
}

.output-preview {
  display: grid;
  gap: 4px;
  padding: 12px 14px;
  border: 1px solid var(--outline);
  border-radius: 12px;
  background: var(--surface-1);
}

.output-preview span {
  color: var(--on-surface-muted);
  font-size: 12px;
}

.output-preview code {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 12px;
}

.advanced-hint {
  margin: 0 0 12px;
  color: var(--on-surface-muted);
  font-size: 12px;
  line-height: 1.5;
}

.check-list {
  display: flex;
  flex-wrap: wrap;
  gap: 14px 18px;
}

.check-list--spaced {
  margin-top: 14px;
}

.wizard-footer {
  display: flex;
  align-items: center;
  gap: 12px;
}

.wizard-footer__spacer {
  flex: 1;
}

</style>
