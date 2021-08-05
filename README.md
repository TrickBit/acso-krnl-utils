ACSO-IOMMU Kernel Patching

This project is about patching linux kernels for ACSO Override
to anable splitting out IOMMU groups on CPU/Motherboard combo's
that make this otherwise impossible.
NOTE: This ACS override patch introduces a security hole that may
perhaps be exploited
See https://www.reddit.com/r/VFIO/comments/bvif8d/official_reason_why_acs_override_patch_is_not_in/
A Copy of the text is included in ACS_Security_Implications.txt


This work is heavily modified derivative of mdPlusPlus's work which
at the time of writing was available here :
https://gist.github.com/mdPlusPlus/031ec2dac2295c9aaf1fc0b0e808e21a

presonal note to mdPlusPlus:
When I started this I had no intention of creating a new script
there were many changes but I had planned to fork and mod.
it all got out of hand and ended up soo far from the original that
patching your original code was no longer viable.
I used your basic logic and went crazy. I added a some functionality (well sort of)
This script is more about fast repeated runs trying to NOT always
re-fetch the latest info and not always recompile or re-extract.
I messed around with deb package naming as well
I planned this as part of a suite that makes the patches and compiles the kernels
I started down this path when Max Ehrlich  (https://gitlab.com/Queuecumber)
announced that he's closed his project and I had a couple of compilation fails

I've accidentally pretty much excluded all non debian based building of the kernels
and spent way to much time with the debian package side of things.
I plan to modularize the code to handle more case - but thats gonna be a to-do
