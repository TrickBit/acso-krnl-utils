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

The author thanks mdPlsPlus for his excellent contribution and hopes
this code is/will be of use to him and looks forward to any contribution

presonal note to mdPlusPlus:
When I started this I had no intention of creating a new script
there were many changes but I had planned to fork and mod.
it all got out of hand and ended up soo far from the original that
patching your original codes was no longer viable.
I used your basic logic and smoothed out some of your code
added a little more functionality (well sort of)
This script is more about fast repeated runs trying to NOT always
re-fetch the latest info and not always recompile or re-extract.
I messed around with deb package naming as well
I planned this as part of a suite that makes the patches and compiles the kernels
I started down this path when Max Ehrlich  (https://gitlab.com/Queuecumber)
announced that he's closed his project and I had a couple of compilation fails
using your script - it was a config thing - not a script problem
