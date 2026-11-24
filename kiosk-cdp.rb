#!/usr/bin/ruby
#
# 透過 Chrome 遠端除錯介面（CDP, 127.0.0.1:$KIOSK_CDP_PORT，預設 9222）操作 kiosk 中的 Canva 頁面。
# 直接連到 Canva 分頁，不經過 AppleScript，因此不會誤操作到同時開著的一般 Chrome。
#
# 用法：
#   kiosk-cdp.rb duration [等待秒數]   輸出簡報總長度（秒）；偵測不到時 exit 1
#   kiosk-cdp.rb play                 確保簡報在播放：沒在播就點播放器的「播放」鈕並確認時間開始前進
#                                     輸出 already-playing / started / clicked / no-button / failed
#   kiosk-cdp.rb state                輸出 playing / paused / unknown
#   kiosk-cdp.rb press-space          在 Canva 頁面送出空白鍵（播放／暫停切換）
#   kiosk-cdp.rb reload               重新載入 Canva 頁面

require "base64"
require "json"
require "net/http"
require "securerandom"
require "socket"
require "uri"

PORT = Integer(ENV.fetch("KIOSK_CDP_PORT", "9222"))
COMMAND = ARGV[0].to_s
WAIT_SECONDS = (ARGV[1] || "15").to_i

unless %w[duration play state press-space reload].include?(COMMAND)
  warn "用法：#{File.basename($PROGRAM_NAME)} duration [秒] | play | state | press-space | reload"
  exit 2
end

# 看門狗：Chrome 沒回應（例如頁面在讀取途中重新載入）時直接以失敗結束，
# 避免主迴圈永遠卡住。
WATCHDOG_SECONDS = { "duration" => WAIT_SECONDS * 2 + 15, "play" => 60 }.fetch(COMMAND, 20)
Thread.new do
  sleep WATCHDOG_SECONDS
  warn "CDP 操作逾時（#{COMMAND}）"
  exit!(1)
end

def read_exact(socket, length)
  data = +""
  data << socket.readpartial(length - data.bytesize) while data.bytesize < length
  data
end

def send_frame(socket, payload)
  bytes = payload.b
  header = [0x81]
  length = bytes.bytesize
  if length < 126
    header << (0x80 | length)
  elsif length <= 65_535
    header << (0x80 | 126)
    header.concat([length].pack("n").bytes)
  else
    header << (0x80 | 127)
    header.concat([length].pack("Q>").bytes)
  end

  mask = SecureRandom.random_bytes(4)
  masked = bytes.bytes.each_with_index.map { |byte, index| byte ^ mask.getbyte(index % 4) }.pack("C*")
  socket.write(header.pack("C*") + mask + masked)
end

def read_message(socket)
  message = +""
  loop do
    first, second = read_exact(socket, 2).bytes
    final = (first & 0x80) != 0
    opcode = first & 0x0f
    length = second & 0x7f
    length = read_exact(socket, 2).unpack1("n") if length == 126
    length = read_exact(socket, 8).unpack1("Q>") if length == 127
    mask = (second & 0x80) != 0 ? read_exact(socket, 4) : nil
    payload = read_exact(socket, length)
    if mask
      payload = payload.bytes.each_with_index.map { |byte, index| byte ^ mask.getbyte(index % 4) }.pack("C*")
    end
    raise EOFError, "WebSocket 已關閉" if opcode == 8
    next if opcode == 9 || opcode == 10
    message << payload
    return message if final
  end
end

def find_canva_target(wait_seconds)
  deadline = Time.now + wait_seconds
  loop do
    begin
      response = Net::HTTP.start("127.0.0.1", PORT, open_timeout: 2, read_timeout: 2) do |http|
        http.get("/json/list").body
      end
      target = JSON.parse(response).find do |item|
        item["type"] == "page" && item["url"].to_s.include?("canva.com/design/")
      end
      return target if target && target["webSocketDebuggerUrl"]
    rescue StandardError
      # Chrome 或頁面仍在載入。
    end
    return nil if Time.now >= deadline
    sleep 0.5
  end
end

def connect(target)
  uri = URI(target["webSocketDebuggerUrl"])
  socket = TCPSocket.new(uri.host, uri.port)
  key = Base64.strict_encode64(SecureRandom.random_bytes(16))
  request_target = uri.path.to_s.empty? ? "/" : uri.path
  request_target += "?#{uri.query}" if uri.query
  socket.write(
    "GET #{request_target} HTTP/1.1\r\n" \
    "Host: #{uri.host}:#{uri.port}\r\n" \
    "Upgrade: websocket\r\n" \
    "Connection: Upgrade\r\n" \
    "Sec-WebSocket-Key: #{key}\r\n" \
    "Sec-WebSocket-Version: 13\r\n\r\n"
  )
  headers = +""
  headers << socket.readpartial(1024) until headers.include?("\r\n\r\n")
  raise "WebSocket 握手失敗" unless headers.start_with?("HTTP/1.1 101")
  socket
end

$next_id = 0

# 送出一個 CDP 指令並等待對應 id 的回應（略過中間收到的事件）。
def cdp(socket, method, params = {})
  id = ($next_id += 1)
  send_frame(socket, JSON.generate(id: id, method: method, params: params))
  loop do
    response = JSON.parse(read_message(socket))
    next unless response["id"] == id
    raise "CDP 錯誤：#{response['error']}" if response["error"]
    return response["result"]
  end
end

def mouse(socket, type, x, y, pressed = false)
  params = { type: type, x: x, y: y }
  params.merge!(button: "left", buttons: pressed ? 1 : 0, clickCount: 1) unless type == "mouseMoved"
  cdp(socket, "Input.dispatchMouseEvent", params)
end

def click_at(socket, x, y)
  mouse(socket, "mouseMoved", x, y)
  mouse(socket, "mousePressed", x, y, true)
  mouse(socket, "mouseReleased", x, y)
end

def evaluate(socket, expression)
  result = cdp(socket, "Runtime.evaluate", expression: expression, awaitPromise: true, returnByValue: true)
  result.dig("result", "value")
end

DURATION_JS = <<~JAVASCRIPT
  new Promise((resolve) => {
    const deadline = Date.now() + #{WAIT_SECONDS * 1000};
    const parseTime = (text) => {
      const parts = String(text).trim().split(':').map(Number);
      if (!parts.length || parts.some(Number.isNaN)) return 0;
      return parts.reduce((total, part) => total * 60 + part, 0);
    };
    const detect = () => {
      const videoDurations = Array.from(document.querySelectorAll('video'))
        .map((video) => Number(video.duration))
        .filter((duration) => Number.isFinite(duration) && duration > 0);
      const displayedTimes = Array.from(document.querySelectorAll('time'))
        .map((item) => parseTime(item.textContent))
        .filter((duration) => duration > 0);
      const durations = videoDurations.concat(displayedTimes);
      if (durations.length) return resolve(Math.max(...durations));
      if (Date.now() >= deadline) return resolve(null);
      setTimeout(detect, 500);
    };
    detect();
  })
JAVASCRIPT

# 確保簡報在播放（以狀態為準，不是切換）：
# Canva 的 /watch 播放器載入後不會自動播放；空白鍵是「播放／暫停」切換，而且要頁面有鍵盤焦點才收得到。
# 做法：先把頁面帶到最前面，觀察 2.5 秒；時間有前進就不動作。否則在「看得見」的「播放」鈕中心
# 送出真正的滑鼠點擊（CDP Input 事件，等同使用者點擊，不需要 macOS 權限），再確認時間開始前進，最多 3 次。
PLAY_LABELS = %w[播放 Play 再生 재생 Reproducir Lire Abspielen Riproduci Reproduzir].freeze
PAUSE_LABELS = %w[暫停 Pause 一時停止 일시정지 Pausa Pausieren].freeze

# 時間（或影片）在 2.5 秒內有沒有前進。
ADVANCING_JS = <<~JAVASCRIPT
  new Promise((resolve) => {
    const times = () => Array.from(document.querySelectorAll('time')).map((item) => item.textContent.trim()).join('|');
    const videoPlaying = () => Array.from(document.querySelectorAll('video'))
      .some((video) => !video.paused && !video.ended && video.readyState > 2);
    const before = times();
    setTimeout(() => resolve(videoPlaying() || before !== times()), 2500);
  })
JAVASCRIPT

# 把元素與所有上層的 opacity 相乘：Canva 會把隱藏的按鈕設成透明，而不是移除。
OPACITY_JS = <<~JAVASCRIPT
  const effectiveOpacity = (el) => {
    let value = 1;
    for (let node = el; node && node.nodeType === 1; node = node.parentElement) value *= parseFloat(getComputedStyle(node).opacity);
    return value;
  };
JAVASCRIPT

# 找出看得見的「播放」鈕，回傳中心座標；找不到回傳 null。
PLAY_BUTTON_JS = <<~JAVASCRIPT
  (() => {
    #{OPACITY_JS}
    const labels = #{JSON.generate(PLAY_LABELS)};
    const candidates = Array.from(document.querySelectorAll('button[aria-label]'))
      .filter((button) => labels.includes(button.getAttribute('aria-label')))
      .map((button) => {
        const rect = button.getBoundingClientRect();
        return { button, rect, opacity: effectiveOpacity(button), x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 };
      })
      .filter(({ rect, opacity }) => rect.width > 0 && rect.height > 0 && opacity > 0.5
        && rect.right > 0 && rect.bottom > 0 && rect.left < innerWidth && rect.top < innerHeight)
      // 中心點真的會點到這顆按鈕（沒有被其他透明按鈕蓋住），才算數。
      .filter(({ button, x, y }) => {
        const hit = document.elementFromPoint(x, y);
        return hit && (hit === button || button.contains(hit));
      })
      .sort((a, b) => b.rect.width * b.rect.height - a.rect.width * a.rect.height);
    if (!candidates.length) return null;
    return { x: candidates[0].x, y: candidates[0].y };
  })()
JAVASCRIPT

# 播放失敗時記錄的頁面狀態，用來判斷是頁面沒在前景、按鈕被隱藏，還是點了沒反應。
DIAGNOSTICS_JS = <<~JAVASCRIPT
  (() => {
    #{OPACITY_JS}
    const labels = #{JSON.generate(PLAY_LABELS + PAUSE_LABELS)};
    return {
      visibility: document.visibilityState,
      focus: document.hasFocus(),
      activated: navigator.userActivation ? navigator.userActivation.hasBeenActive : null,
      viewport: [innerWidth, innerHeight],
      times: Array.from(document.querySelectorAll('time')).map((item) => item.textContent.trim()),
      videos: document.querySelectorAll('video').length,
      buttons: Array.from(document.querySelectorAll('button[aria-label]'))
        .filter((button) => labels.includes(button.getAttribute('aria-label')))
        .map((button) => {
          const rect = button.getBoundingClientRect();
          return `${button.getAttribute('aria-label')}@${Math.round(rect.left)},${Math.round(rect.top)} ` +
            `${Math.round(rect.width)}x${Math.round(rect.height)} op=${effectiveOpacity(button).toFixed(2)}`;
        }),
    };
  })()
JAVASCRIPT

# 判斷是否正在播放：比較 2.5 秒前後播放器上的時間文字。
# 時間有變化或有影片在播 → playing；有「目前時間＋總長度」兩個以上時間但都沒動 → paused；
# 其餘無法確定 → unknown（呼叫端遇到 unknown 不做任何動作，以免誤把播放中的簡報暫停）。
STATE_JS = <<~JAVASCRIPT
  new Promise((resolve) => {
    const snapshot = () => Array.from(document.querySelectorAll('time')).map((item) => item.textContent.trim());
    const before = snapshot();
    setTimeout(() => {
      const after = snapshot();
      const videoPlaying = Array.from(document.querySelectorAll('video'))
        .some((video) => !video.paused && !video.ended && video.readyState > 2);
      if (videoPlaying || before.join('|') !== after.join('|')) return resolve('playing');
      if (before.length >= 2 && before.length === after.length) return resolve('paused');
      resolve('unknown');
    }, 2500);
  })
JAVASCRIPT

begin
  target = find_canva_target(COMMAND == "duration" ? WAIT_SECONDS : 5)
  exit 1 unless target
  socket = connect(target)

  case COMMAND
  when "duration"
    value = evaluate(socket, DURATION_JS)
    exit 1 unless value.is_a?(Numeric) && value.positive?
    puts value.ceil
  when "play"
    # 先把 kiosk 分頁帶到最前面：頁面在背景時 Chrome 會暫停動畫，Canva 的時間軸不會前進。
    begin
      cdp(socket, "Page.bringToFront")
    rescue StandardError
      nil
    end
    # 等頁面載入完成（最多 15 秒），播放器的按鈕才會有反應。
    15.times do
      break if evaluate(socket, "document.readyState") == "complete"
      sleep 1
    end
    result =
      if evaluate(socket, ADVANCING_JS) == true
        "already-playing"
      else
        outcome = nil
        3.times do |attempt|
          # 重試之間隔 3 秒：播放器可能還沒準備好，連續快速點擊只會全部落空。
          sleep 3 if attempt.positive?
          position = evaluate(socket, PLAY_BUTTON_JS)
          unless position
            # 控制列可能已自動隱藏：把滑鼠移到畫面中央讓它出現，再找一次。
            width, height = evaluate(socket, "[innerWidth, innerHeight]")
            mouse(socket, "mouseMoved", width / 2.0, height / 2.0)
            sleep 1
            position = evaluate(socket, PLAY_BUTTON_JS)
          end
          unless position
            outcome = "no-button"
            break
          end
          click_at(socket, position["x"], position["y"])
          if evaluate(socket, "document.querySelectorAll('time, video').length").to_i.zero?
            outcome = "clicked" # 頁面上沒有時間也沒有影片，無法確認，點過就算數。
            break
          end
          if evaluate(socket, ADVANCING_JS) == true
            outcome = "started"
            break
          end
        end
        outcome || "failed"
      end
    puts result
    unless %w[already-playing started clicked].include?(result)
      warn "播放診斷：#{JSON.generate(evaluate(socket, DIAGNOSTICS_JS))}"
    end
  when "state"
    puts evaluate(socket, STATE_JS) || "unknown"
  when "press-space"
    # CDP 送出的按鍵是受信任事件，不需要「輔助使用」權限，也不受視窗焦點影響。
    key = { key: " ", code: "Space", windowsVirtualKeyCode: 32, nativeVirtualKeyCode: 32 }
    cdp(socket, "Input.dispatchKeyEvent", key.merge(type: "keyDown", text: " "))
    cdp(socket, "Input.dispatchKeyEvent", key.merge(type: "keyUp"))
  when "reload"
    cdp(socket, "Page.reload", ignoreCache: false)
  end
  exit 0
rescue StandardError => e
  warn "CDP 失敗（#{COMMAND}）：#{e.message}"
  exit 1
end
