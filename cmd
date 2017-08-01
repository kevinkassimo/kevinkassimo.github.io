#!/bin/bash

case $1 in
    "serve")
        bundle exec jekyll serve
        exit 0
        ;;
    "commit")
        git add .
        git commit -m "$2"
        git push origin master
        exit 0
        ;;
    "pull")
        git pull
        exit 0
        ;;
esac

