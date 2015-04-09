(ns illusen.core
  (:require [pixie.uv :as uv]
            [pixie.io :as io]
            [pixie.ffi :as ffi]
            [pixie.ffi-infer :as f]
            [pixie.async :as async]))

(defn make-request-state []
  (atom {:contents ""
         :promise (async/promise)}))

; not really happy with the structure of this, but it will have to do for now
; I'm not sure this thing is really a win
(defmacro defn-callback [tp state-binding nm args & body]
  `(def ~nm
     (fn ~state-binding
       (ffi/ffi-prep-callback ~tp (fn ~args ~@body)))))

(defn-callback
  uv/uv_alloc_cb [state]
  on-alloc [handle size buf-ptr]
  (let [buf (ffi/cast buf-ptr uv/uv_buf_t)
        b (buffer size)]
    (pixie.ffi/set! buf :base b)
    (pixie.ffi/set! buf :len size)))

(defn buffer-with-contents [s]
  (let [buf (uv/uv_buf_t)
        len (count s)
        s (ffi/prep-string s)]
    (pixie.ffi/set! buf :base s)
    (pixie.ffi/set! buf :len len)
    buf))

(defn-callback
  uv/uv_connect_cb [state]
  on-connect [connect s]
  (let [handle-ptr (:handle (ffi/cast connect uv/uv_connect_t))
        handle (ffi/cast handle-ptr uv/uv_stream_t)
        request (uv/uv_write_t)]
    (uv/uv_write request handle buf 1 (on-write state))
    (uv/uv_read_start handle (on-alloc state) (on-read state))))

(defn-callback
  uv/uv_write_cb [state]
  on-write [req status]
  (if (neg? status) (prn (uv/uv_err_name status))))

(defn-callback
  uv/uv_close_cb [state]
  on-close [handle]
  ((:promise @state) (:contents @state)))

(defn read-bytes-from-buf-ptr [nread buf]
  (let [buf (:base (ffi/cast buf uv/uv_buf_t))]
    (apply str (map #(char (ffi/unpack buf % CUInt8)) (range 0 nread)))))

; this seems weird, but the on-read is not getting called with nread = 0, so
; maybe we have to check if the content-length is met to stop reading?
; that seems wrong and oddly specific to http though, so that seems wrong.
; I need to understand the interface of libuv better.

; hah, the problem was that http 1.1 is keep-alive by default, so changing it
; to Connection: close fixed the problem.
; should look at how other libraries deal with this, but I think the default
; for us should probably be close? unless we provide some wrapper allowing one
; to reuse connections, that might be neat

(defn-callback
  uv/uv_read_cb [state]
  on-read [tcp nread buf]
  (prn nread)
  (if (>= nread 0)
    (let [contents (read-bytes-from-buf-ptr nread buf)]
      (swap! state #(assoc % :contents (str (:contents %) contents)))
      (prn @state))
    (uv/uv_close tcp (on-close state))))

(defn make-addr [hostname port]
  (let [hostname (ffi/prep-string hostname)
        addr (uv/sockaddr_in)
        buf (buffer 1024)]
    (uv/uv_ip4_addr hostname port (ffi/ptr-add addr 0))
    (uv/uv_ip4_name (ffi/ptr-add addr 0) buf 1024)
    (prn
      (apply str (map #(char (ffi/unpack buf % CUInt8)) (range 0 15))))
    addr))

(defn make-request []
  (let [state (make-request-state)
        socket (uv/uv_tcp_t)
        _ (uv/uv_tcp_init (uv/uv_default_loop) socket)
        connect (uv/uv_connect_t)
        addr (make-addr "192.241.166.250" 80)]
    (uv/uv_tcp_connect connect socket addr (on-connect state))
    (:promise @state)))

(def buf (buffer-with-contents
"GET / HTTP/1.1
User-Agent: curl/7.37.1
Connection: close
Host: whocouldthat.be
Accept: */*

"))

(prn @(make-request))
