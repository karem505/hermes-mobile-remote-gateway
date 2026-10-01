/**
 * Pull Session — Hermes desktop plugin
 *
 * "Pull" a chat this device does not own to THIS window:
 *   ⌘K → "اسحب الجلسة إلى هذا الجهاز"  (session.takeover)
 * Also toasts when another device pulls a session away from this window
 * (session.taken_over, emitted by the backend that released it).
 *
 * Backend pair lives in tui_gateway/session_takeover.py + hermes_cli/active_sessions_takeover.py.
 * If the pull command reports the method is unknown, this window's backend predates the
 * feature — restarting the desktop app once is enough.
 */

import { host, haptic } from '@hermes/plugin-sdk'

const ID = 'pull-session'

const SURFACES = {
  desktop: 'سطح المكتب',
  mobile: 'الجوال',
  tui: 'الطرفية',
  cli: 'الطرفية',
  gateway: 'البوت',
  bot: 'البوت'
}

const surfaceAr = (s) => SURFACES[String(s || '').toLowerCase()] || 'جهاز آخر'

async function pullToThisDevice() {
  const sid = host.state.focusedSessionId.get() || host.state.focusedStoredSessionId.get()
  if (!sid) {
    host.notify({ kind: 'warning', message: 'لا توجد جلسة مفتوحة لسحبها.' })
    return
  }
  try {
    const r = await host.request('session.takeover', { session_id: sid }, 30000)
    const status = (r && r.status) || 'ok'
    const from = r && r.holder_surface ? ` من ${surfaceAr(r.holder_surface)}` : ''
    host.notify({
      kind: 'info',
      message: status === 'already' ? 'هذه الجلسة على هذا الجهاز بالفعل.' : `تم سحب الجلسة${from} إلى هذا الجهاز.`
    })
  } catch (e) {
    const err = e && typeof e === 'object' ? e : {}
    const data = err.data && typeof err.data === 'object' ? err.data : {}
    if (err.code === -32601) {
      host.notifyError('ميزة سحب الجلسة تحتاج إعادة تشغيل تطبيق الديسكتوب مرة واحدة.', 'سحب الجلسة')
      return
    }
    if (data.reason === 'TAKEOVER_BUSY') {
      host.notify({
        kind: 'warning',
        message: `الجلسة تعمل الآن على ${surfaceAr(data.holder_surface)} ولم ينتهِ دورها بعد؛ أوقفه من هناك ثم أعد المحاولة.`
      })
      return
    }
    if (data.reason === 'TAKEOVER_RACED') {
      host.notify({ kind: 'warning', message: 'بدأت الجلسة دورًا جديدًا على الجهاز الآخر؛ انتظر لحظة ثم أعد المحاولة.' })
      return
    }
    host.notifyError(String(err.message || e || 'خطأ'), 'تعذر سحب الجلسة')
  }
}

export default {
  id: ID,
  name: 'سحب الجلسة بين الأجهزة',
  defaultEnabled: true,
  register(ctx) {
    ctx.register({
      id: 'pull',
      area: 'palette',
      data: {
        id: 'session.pull-to-this-device',
        label: 'اسحب الجلسة إلى هذا الجهاز (Pull session here)',
        keywords: ['pull', 'takeover', 'session', 'سحب', 'جلسة', 'هنا'],
        run: () => {
          haptic('tap')
          void pullToThisDevice()
        }
      }
    })

    ctx.onEvent('session.taken_over', (event) => {
      const p = (event && event.payload) || {}
      host.notify({
        kind: 'info',
        message: `سُحبت هذه الجلسة إلى ${surfaceAr(p.by)}؛ لإكمال العمل من هنا استخدم "اسحب الجلسة إلى هذا الجهاز".`
      })
    })
  }
}
