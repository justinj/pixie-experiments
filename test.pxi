(ns illusen.core
  (:require [pixie.uv :as uv]
            [pixie.io :as io]
            [pixie.ffi :as ffi]
            [pixie.ffi-infer :as f]
            [pixie.async :as async]))

; (f/with-config {:library "c"
;                 :includes ["sys/socket.h"]}
;   (f/defcstruct sockaddr []))

; (def lp (uv/uv_default_loop))

; (def tcp (uv/uv_tcp_t))
; (uv/uv_tcp_init lp tcp)

; (def s (uv/sockaddr_in))

; (uv/uv_ip4_addr "0.0.0.0" 8888 s)

; (uv/uv_tcp_bind tcp s 0)

; (uv/uv_run lp uv/UV_RUN_DEFAULT)

; (def r (uv/


(def socket (uv/uv_tcp_t))
(uv/uv_tcp_init (uv/uv_default_loop) socket)

(def connect (uv/uv_connect_t))
(def addr (uv/sockaddr_in))
(uv/uv_ip4_addr "127.0.0.1" 8000 addr)

(defn on-alloc [handle size buf-ptr]
  (let [buf (ffi/cast buf-ptr uv/uv_buf_t)
        b (buffer size)]
    (pixie.ffi/set! buf :base b)
    (pixie.ffi/set! buf :len size)
    ; (pixie.ffi/pack! buf-ptr 0 CVoidP buf)
    ))

(def alloc-cb (ffi/ffi-prep-callback uv/uv_alloc_cb on-alloc))

(defn buffer-with-contents [s]
  (let [buf (uv/uv_buf_t)
        len (count s)
        s (ffi/prep-string s)]
    (pixie.ffi/set! buf :base s)
    (pixie.ffi/set! buf :len len)
    buf))

; TODO: unsure what the user-agent should be...
(def buf (buffer-with-contents "GET / HTTP/1.1
User-Agent: pixie
Host: localhost:8000
Accept: */*

"))

(defn on-connect [connect s]
  ; TODO: check status here
  (def handle-ptr (:handle (ffi/cast connect uv/uv_connect_t)))
  (def handle (ffi/cast handle-ptr uv/uv_stream_t))

  (uv/uv_write request handle buf 1 write-cb)
  (uv/uv_read_start handle alloc-cb read-cb))

(def cb (ffi/ffi-prep-callback uv/uv_connect_cb on-connect))

(def request (uv/uv_write_t))

(defn on-write [req status]
  (if (neg? status) (prn (uv/uv_err_name status)))
  0)

(def write-cb (ffi/ffi-prep-callback uv/uv_write_cb on-write))

(defn on-close [handle]
  (prn "closed.")
  0)

(def close-cb (ffi/ffi-prep-callback uv/uv_close_cb on-close))

(defn read-bytes-from-buf [nread buf]
  (apply str (map #(char (ffi/unpack buf % CUInt8)) (range 0 nread))))

(defn on-read [tcp nread buf]
  (if (>= nread 0)
    (prn (read-bytes-from-buf
           nread
           (:base (ffi/cast buf uv/uv_buf_t))))
    (uv/uv_close tcp close-cb))
  0)

(def read-cb (ffi/ffi-prep-callback uv/uv_read_cb on-read))

(uv/uv_tcp_connect connect socket addr cb)

; (uv/uv_run (uv/uv_default_loop) uv/UV_RUN_DEFAULT)
