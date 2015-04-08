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
  ; TODO: check status here
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

(defn read-bytes-from-buf [nread buf]
  (apply str (map #(char (ffi/unpack buf % CUInt8)) (range 0 nread))))

(defn-callback
  uv/uv_read_cb [state]
  on-read [tcp nread buf]
  (if (>= nread 0)
    (let [contents (read-bytes-from-buf
                     nread
                     (:base (ffi/cast buf uv/uv_buf_t)))]
      (swap! state #(assoc % :contents (str (:contents %) contents))))
    (uv/uv_close tcp (on-close state))))

(defn make-addr [hostname port]
  (let [addr (uv/sockaddr_in)]
    (uv/uv_ip4_addr hostname port addr)
    addr))

(defn make-request []
  (let [state (make-request-state)
        socket (uv/uv_tcp_t)
        _ (uv/uv_tcp_init (uv/uv_default_loop) socket)
        connect (uv/uv_connect_t)
        addr (make-addr "localhost" 8000)]
    (uv/uv_tcp_connect connect socket addr (on-connect state))
    (:promise @state)))

; TODO: unsure what the user-agent should be...
(def buf (buffer-with-contents "GET / HTTP/1.1
User-Agent: pixie
Host: localhost:8000
Accept: */*

"))

(prn @(make-request))
