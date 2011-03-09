#!/bin/sh

for i in $(getargs rdloaddriver=); do 
    ( 
        IFS=,
        for p in $i; do 
            modprobe $p 2>&1 | vinfo
        done
    )
done

