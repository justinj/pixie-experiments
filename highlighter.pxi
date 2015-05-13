(ns co480
  (:require [sparkles.core :as sparkles]
            [pixie.string :as string]))

(def col (sparkles/color {:fg :blue}))

(def text  "test")

(def letters (filter #(not (or (= \newline %) (= \space %))) text))
(def ads (map vec (partition 2 1 letters)))
(prn (filter (fn [[[x y] _]] (= x y)) (frequencies ads)))

(def translations
  {\D \T
   \Q \H
   \Z \E

   \M \A

   \E \O

   ; maybes
   ; not \F \R
   ; \M \O
   ; \Y \A
   ; \E \I

   ; \L \D

   ; \C \O
   })

(prn translations)
(println (frequencies text))

(def spaced (string/replace (apply str letters) "DQZ" " DQZ\n"))

(for [t spaced]
  (if (contains? translations t)
    (print (col (translations t)))
    (print t)))
