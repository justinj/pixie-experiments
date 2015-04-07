(ns illusen.core
  (:require [pixie.uv :as uv]
            [pixie.io :as io]
            [pixie.ffi :as ffi]
            [pixie.ffi-infer :as f]
            [pixie.async :as async]))

(defmacro defn-callback [tp nm args & body]
  `(let [f# (fn ~args ~@body)]
     (def ~nm (ffi/ffi-prep-callback ~tp f#))))

(defn-callback uv/uv_alloc_cb
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

(defn-callback uv/uv_connect_cb
  on-connect [connect s]
  ; TODO: check status here
  (let [handle-ptr (:handle (ffi/cast connect uv/uv_connect_t))
        handle (ffi/cast handle-ptr uv/uv_stream_t)
        request (uv/uv_write_t)]
    (uv/uv_write request handle buf 1 on-write)
    (uv/uv_read_start handle on-alloc on-read)))

(defn-callback uv/uv_write_cb
  on-write [req status]
  (if (neg? status) (prn (uv/uv_err_name status)))
  0)

(defn-callback uv/uv_close_cb
  on-close [handle])

(defn read-bytes-from-buf [nread buf]
  (apply str (map #(char (ffi/unpack buf % CUInt8)) (range 0 nread))))

(defn-callback uv/uv_read_cb
  on-read [tcp nread buf]
  (if (>= nread 0)
    (println (read-bytes-from-buf
           nread
           (:base (ffi/cast buf uv/uv_buf_t))))
    (uv/uv_close tcp on-close))
  0)

(defn make-addr [hostname port]
  (let [addr (uv/sockaddr_in)]
    (uv/uv_ip4_addr hostname port addr)
    addr))

(defn make-request []
  (let [socket (uv/uv_tcp_t)
        _ (uv/uv_tcp_init (uv/uv_default_loop) socket)
        connect (uv/uv_connect_t)
        addr (make-addr "localhost" 8000)]
    (uv/uv_tcp_connect connect socket addr on-connect)))

; TODO: unsure what the user-agent should be...
(def buf (buffer-with-contents "GET / HTTP/1.1
User-Agent: pixie
Host: localhost:8000
Accept: */*

"))

(make-request)
