# SPDX-License-Identifier: GPL-2.0
#
# Makefile for kernel SLIMbus framework.
#

# trace.h sets TRACE_INCLUDE_PATH to "." and is re-included through
# include/trace/define_trace.h, so this directory must be on the include path.
ccflags-y += -I$(src)

obj-$(CONFIG_SLIMBUS)			+= slimbus.o
slimbus-y				:= core.o messaging.o sched.o stream.o

#Controllers
obj-$(CONFIG_SLIM_QCOM_CTRL)		+= slim-qcom-ctrl.o
slim-qcom-ctrl-y			:= qcom-ctrl.o

obj-$(CONFIG_SLIM_QCOM_NGD_CTRL)	+= slim-qcom-ngd-ctrl.o
slim-qcom-ngd-ctrl-y			:= qcom-ngd-ctrl.o
