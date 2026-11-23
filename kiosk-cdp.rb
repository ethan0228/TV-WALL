#!/usr/bin/ruby
#
# 透過 Chrome 遠端除錯介面（CDP, 127.0.0.1:9222）操作 kiosk 中的 Canva 頁面。
# 直接連到 Canva 分頁，不經過 AppleScript，因此不會誤操作到同時開著的一般 Chrome。
#
# 用法：
#   kiosk-cdp.rb duration [等待秒數]   輸出簡報總長度（秒）；偵測不到時 exit 1
#   kiosk-cdp.rb state                輸出 playing / paused / unknown
#   kiosk-cdp.rb press-space          在 Canva 頁面送出空白鍵（播放／暫停切換）
#   kiosk-cdp.rb reload               重新載入 Canva 頁面

require "base64"
require "json"
require "net/http"
require "securerandom"
require "socket"
require "uri"

PORT = 9222
COMMAND = ARGV[0].to_s
WAIT_SECONDS = (ARGV[1] || "15").to_i

unless %w[duration state press-space reload].include?(COMMAND)
  warn "用法：#{File.basename($PROGRAM_NAME)} duration [秒] | state | press-space | reload"
  exit 2
end

# 看門狗：Chrome 沒回應（例如頁面在讀取途中重新載入）時直接以失敗結束，
# 避免主迴圈永遠卡住。
WATCHDOG_SECONDS = COMMAND == "duration" ? WAIT_SECONDS * 2 + 15 : 20
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
