#!/bin/bash

ttestlib_dir=$(dirname "$(readlink -f "${0}")")


source "$ttestlib_dir/tblib"
source "$ttestlib_dir/tbxmalib"

function mytrap()
{
  printf "Trapped!\n"
  printf '%s' "$IFS"
	printf '%s' "$IFS" | od -bc
}
trap mytrap SIGINT SIGTERM ERR EXIT

printf '%s' "$IFS"
printf '%s' "$IFS" | od -bc

test_customarray >> /dev/null
printf '%s' "$IFS"
printf '%s' "$IFS" | od -bc
