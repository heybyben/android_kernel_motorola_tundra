# SPDX-License-Identifier: GPL-2.0
# bam_dma_trace.h sets TRACE_INCLUDE_PATH to "." and is re-included through
# include/trace/define_trace.h, so this directory must be on the include path.
ccflags-y += -I$(src)

obj-$(CONFIG_QCOM_ADM) += qcom_adm.o
obj-$(CONFIG_QCOM_BAM_DMA) += bam_dma.o
obj-$(CONFIG_QCOM_GPI_DMA) += gpi.o
obj-$(CONFIG_MSM_GPI_DMA) += msm_gpi.o
obj-$(CONFIG_QCOM_HIDMA_MGMT) += hdma_mgmt.o
hdma_mgmt-objs	 := hidma_mgmt.o hidma_mgmt_sys.o
obj-$(CONFIG_QCOM_HIDMA) +=  hdma.o
hdma-objs        := hidma_ll.o hidma.o hidma_dbg.o
obj-$(CONFIG_QCOM_PCI_EDMA) += pci-edma.o
