#!/usr/bin/ruby

require "base64"
require "json"
require "net/http"
require "securerandom"
require "socket"
require "uri"

PORT = 9222
WAIT_SECONDS = (ARGV[0] || "15").to_i

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
    next if opcode == 9 || opcode == 10
    message << payload
    return message if final
  end
end

deadline = Time.now + WAIT_SECONDS
target = nil

until target || Time.now >= deadline
  begin
    response = Net::HTTP.get(URI("http://127.0.0.1:#{PORT}/json/list"))
    targets = JSON.parse(response)
    target = targets.find { |item| item["type"] == "page" && item["url"].to_s.include?("canva.com/design/") }
  rescue StandardError
    # Chrome 或頁面仍在載入。
  end
  sleep 0.5 unless target
end

exit 1 unless target && target["webSocketDebuggerUrl"]

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
exit 1 unless headers.start_with?("HTTP/1.1 101")

expression = <<~JAVASCRIPT
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

command = {
  id: 1,
  method: "Runtime.evaluate",
  params: {
    expression: expression,
    awaitPromise: true,
    returnByValue: true
  }
}
send_frame(socket, JSON.generate(command))

loop do
  response = JSON.parse(read_message(socket))
  next unless response["id"] == 1
  value = response.dig("result", "result", "value")
  if value.is_a?(Numeric) && value.positive?
    puts value.ceil
    exit 0
  end
  exit 1
end
