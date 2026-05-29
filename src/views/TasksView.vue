<script setup lang="ts">
import { computed, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useMessage } from 'naive-ui'
import {
  CheckmarkCircleOutline,
  AlertCircleOutline,
  CloseCircleOutline,
  HourglassOutline,
  FolderOpenOutline,
  RefreshOutline,
  TrashOutline,
} from '@vicons/ionicons5'
import { useTaskStore, type SeparationTask } from '@/stores/task'

const { t } = useI18n()
const message = useMessage()
const task = useTaskStore()

const terminalStatuses = ['done', 'failed', 'cancelled']
const runningCount = computed(() => task.runningTasks.length)
const doneCount = computed(() => task.completedTasks.length)
const showLogModal = ref(false)
const selectedLogTask = ref<SeparationTask | null>(null)

function formatTime(value: number) {
  return new Date(value).toLocaleString()
}

function openOutput(item: SeparationTask) {
  task.revealPath(item.outputs[0]?.path || item.output)
}

function openLogs(item: SeparationTask) {
  selectedLogTask.value = item
  showLogModal.value = true
}

function logClass(line: string) {
  const value = line.toLowerCase()
  if (value.includes('error') || value.includes('failed') || value.includes('traceback')) return 'log-line--error'
  if (value.includes('warn')) return 'log-line--warn'
  if (value.includes('debug')) return 'log-line--debug'
  if (value.includes('done') || value.includes('success') || value.includes('completed')) return 'log-line--success'
  return 'log-line--info'
}

async function handleCancel(id: string) {
  const ok = await task.cancelTask(id)
  if (ok) message.success('Cancelled')
}

async function handleRetry(id: string) {
  try {
    await task.retryTask(id)
    message.success(t('toast.taskRetried'))
  } catch (err) {
    message.error(err instanceof Error ? err.message : String(err))
  }
}


function statusLabel(status: string) {
  const labels: Record<string, string> = {
    queued: 'Queued',
    preparing: 'Preparing',
    validating_input: 'Validating',
    downloading_model: 'Checking model',
    ensuring_model: 'Checking model',
    loading_model: 'Loading model',
    separating: 'Separating',
    writing_output: 'Writing output',
    done: 'Done',
    failed: 'Failed',
    cancelled: 'Cancelled',
  }
  return labels[status] || status
}

function progressStatus(status: string) {
  switch (status) {
    case 'done': return 'success' as const
    case 'failed': return 'error' as const
    case 'cancelled': return 'warning' as const
    default: return 'info' as const
  }
}

function isRunning(status: string) {
  return !terminalStatuses.includes(status)
}

function taskDuration(item: SeparationTask) {
  const seconds = Math.max(0, Math.round((item.updatedAt - item.createdAt) / 1000))
  if (seconds < 60) return `${seconds}s`
  const minutes = Math.floor(seconds / 60)
  const rest = seconds % 60
  return `${minutes}m ${rest}s`
}

function statusIcon(status: string) {
  switch (status) {
    case 'done': return CheckmarkCircleOutline
    case 'failed': return AlertCircleOutline
    case 'cancelled': return CloseCircleOutline
    default: return HourglassOutline
  }
}

function statusType(status: string) {
  switch (status) {
    case 'done': return 'success' as const
    case 'failed': return 'error' as const
    case 'cancelled': return 'default' as const
    default: return 'info' as const
  }
}
</script>

<template>
  <div class="page">
    <div class="page-header-compact">
      <div>
        <h1>{{ t('tasks.title') }}</h1>
        <p>{{ t('tasks.subtitle') }}</p>
        <div v-if="task.tasks.length" class="task-summary">
          <span>{{ runningCount }} 个进行中</span>
          <span>{{ doneCount }} 个已完成</span>
          <span>{{ task.tasks.length }} 个总任务</span>
        </div>
      </div>
      <n-button v-if="task.tasks.length" secondary @click="task.clearHistory()">
        <template #icon><n-icon :component="TrashOutline" /></template>
        {{ t('tasks.clearHistory') }}
      </n-button>
    </div>

    <!-- Empty State -->
    <n-card v-if="!task.tasks.length" :bordered="true">
      <div style="text-align:center;padding:32px 0">
        <n-icon :component="HourglassOutline" size="48" color="var(--on-surface-muted)" />
        <p class="text-muted mt-md">{{ t('tasks.empty') }}</p>
      </div>
    </n-card>

    <!-- Task List -->
    <div v-else style="display:grid;gap:12px">
      <n-card
        v-for="item in task.tasks"
        :key="item.id"
        :bordered="true"
        :segmented="{ content: true }"
        size="small"
      >
        <template #header>
          <div class="flex-between" style="flex:1">
            <div>
              <strong style="font-size:14px">{{ item.input.split(/[/\\]/).pop() || item.input }}</strong>
              <span class="text-muted" style="font-size:12px;margin-left:8px">{{ item.model }}</span>
            </div>
            <n-tag :type="statusType(item.status)" :bordered="false" size="small">
              <template #icon><n-icon :component="statusIcon(item.status)" /></template>
              {{ statusLabel(item.status) }}
            </n-tag>
          </div>
        </template>

        <div class="task-progress-block">
          <div class="task-progress-head">
            <span>{{ item.stageLabel || statusLabel(item.status) }}</span>
            <span>{{ Math.round(item.progress || 0) }}%</span>
          </div>
          <n-progress
            type="line"
            :percentage="Math.round(item.progress || 0)"
            :status="progressStatus(item.status)"
            :processing="isRunning(item.status)"
            :height="8"
            :show-indicator="false"
          />
          <p class="text-muted text-sm task-message">{{ item.message }}</p>
        </div>
        <div style="display:flex;gap:8px;margin-top:10px;flex-wrap:wrap">
          <n-button
            v-if="isRunning(item.status)"
            size="tiny"
            secondary
            @click="handleCancel(item.id)"
          >
            {{ t('common.cancel') }}
          </n-button>
          <n-button
            v-if="['failed','cancelled'].includes(item.status)"
            size="tiny"
            secondary
            @click="handleRetry(item.id)"
          >
            <template #icon><n-icon :component="RefreshOutline" /></template>
            {{ t('tasks.retry') }}
          </n-button>
          <n-button size="tiny" secondary :disabled="!item.output" @click="task.revealPath(item.output)">
            <template #icon><n-icon :component="FolderOpenOutline" /></template>
            {{ t('tasks.openOutput') }}
          </n-button>
          <n-button size="tiny" secondary :disabled="!item.outputs.length" @click="openOutput(item)">
            {{ t('tasks.openFirstOutput') }}
          </n-button>
          <n-button size="tiny" secondary :disabled="!item.logs.length" @click="openLogs(item)">
            Logs
          </n-button>
          <n-button size="tiny" quaternary @click="task.removeTask(item.id)">
            {{ t('tasks.remove') }}
          </n-button>
        </div>

        <!-- Outputs -->
        <div v-if="item.outputs.length" class="mt-md">
          <strong class="text-sm">{{ t('tasks.outputs') }}</strong>
          <div class="mt-sm" style="display:grid;gap:6px">
            <div v-for="output in item.outputs" :key="output.path" class="task-output-row">
              <n-tag size="tiny" :bordered="false">{{ output.stem }}</n-tag>
              <code>{{ output.path }}</code>
              <n-button size="tiny" quaternary @click="task.revealPath(output.path)">{{ t('common.open') }}</n-button>
            </div>
          </div>
        </div>

        <template #footer>
          <div class="task-footer-meta">
            <span>创建：{{ formatTime(item.createdAt) }}</span>
            <span>更新：{{ formatTime(item.updatedAt) }}</span>
            <span>耗时：{{ taskDuration(item) }}</span>
          </div>
        </template>
      </n-card>
    </div>


    <n-modal v-model:show="showLogModal" style="width:min(960px, 92vw)">
      <n-card
        :title="selectedLogTask ? `${selectedLogTask.input.split(/[/\\]/).pop() || selectedLogTask.input} - Logs` : 'Logs'"
        :bordered="false"
        size="small"
        role="dialog"
        aria-modal="true"
      >
        <template #header-extra>
          <n-tag v-if="selectedLogTask" size="small" :bordered="false" :type="statusType(selectedLogTask.status)">
            {{ statusLabel(selectedLogTask.status) }} / {{ selectedLogTask.logs.length }} lines
          </n-tag>
        </template>

        <div v-if="selectedLogTask?.logs.length" class="log-console">
          <div
            v-for="(line, index) in selectedLogTask.logs"
            :key="`${index}-${line}`"
            class="log-line"
            :class="logClass(line)"
          >
            <span class="log-line-number">{{ String(index + 1).padStart(3, '0') }}</span>
            <span class="log-line-text">{{ line }}</span>
          </div>
        </div>
        <div v-else class="log-empty">No logs yet.</div>

        <template #footer>
          <div class="log-modal-footer">
            <span v-if="selectedLogTask" class="text-muted">{{ selectedLogTask.id }}</span>
            <n-button size="small" @click="showLogModal = false">Close</n-button>
          </div>
        </template>
      </n-card>
    </n-modal>
  </div>
</template>


<style scoped>
.task-summary {
  display: flex;
  gap: 12px;
  margin-top: 8px;
  color: var(--on-surface-muted);
  font-size: 12px;
  flex-wrap: wrap;
}

.task-progress-block {
  margin-top: 2px;
}

.task-progress-head {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 6px;
  color: var(--on-surface);
  font-size: 12px;
  font-weight: 600;
}

.task-message {
  margin: 6px 0 0;
}

.task-footer-meta {
  display: flex;
  gap: 12px;
  flex-wrap: wrap;
  color: var(--on-surface-muted);
  font-size: 12px;
}

.log-console {
  max-height: min(62vh, 620px);
  overflow: auto;
  padding: 12px 0;
  border: 1px solid rgba(255, 255, 255, 0.10);
  border-radius: 12px;
  background:
    linear-gradient(180deg, rgba(255,255,255,0.04), rgba(255,255,255,0.01)),
    #10141b;
  color: #d6deeb;
  font-family: "JetBrains Mono", "Fira Code", Consolas, monospace;
  font-size: 12px;
  line-height: 1.65;
}

.log-line {
  display: grid;
  grid-template-columns: 52px minmax(0, 1fr);
  gap: 10px;
  padding: 1px 14px;
  white-space: pre-wrap;
  word-break: break-word;
}

.log-line:hover {
  background: rgba(255, 255, 255, 0.055);
}

.log-line-number {
  user-select: none;
  color: #5e6a7d;
  text-align: right;
}

.log-line--info .log-line-text { color: #d6deeb; }
.log-line--debug .log-line-text { color: #82aaff; }
.log-line--success .log-line-text { color: #7ee787; }
.log-line--warn .log-line-text { color: #ffd166; }
.log-line--error .log-line-text { color: #ff6b7a; }

.log-empty {
  padding: 28px;
  text-align: center;
  color: var(--on-surface-muted);
}

.log-modal-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

</style>
