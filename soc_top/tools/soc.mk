# useful utilities for board Makefiles that build the SoC

# TODO: Executing xst to just read the version number takes a second.
# Could try to read it from path to XST or a file.
#XST_VERSION := $(shell xst -help | head -1 | sed -n 's/^.*Release \([^ ]*\) .*/\1/p')

include $(dir $(lastword $(MAKEFILE_LIST)))common.mk

################################################################################
# Build config.h and config.vhd files from CONFIG_* variables
################################################################################

# Create config.h and config.vhd from make variables, which will then
# be included in config/config.vhd to create config/config.vhh. This
# is how the configuration is passed to the vhdl.

# A few tricks are used to avoid repeating the config variables names.
# Define a \n var to contain a new line.
define \n


endef
# .VARIABLES contains all variables. Filter it to just the CONFIG_* variables.
CONF_VARS:=$(sort $(filter CONFIG_%,$(.VARIABLES)))
# Create a variable containing a #define line for each var with its value
CONF_HEADER:=$(foreach v,$(CONF_VARS),\#define $v ${$v}${\n})
# export the variable so the shell can access it. See $$ below.
export CONF_HEADER
config/config.h: force
	$(info Creating config/config.h containing $(foreach v,$(CONF_VARS),${v}=${$v}))
	mkdir -p config
	@echo "/* This file is generated by the makefile */" > $@.temp
# use two $$ here so that shell translates the CONF_HEADER variable
# and keeps the newlines
	@echo "$$CONF_HEADER" >> $@.temp
# only replace the file if the new one is different to prevent
# unneeded rebuilding
	@cmp -s $@.temp $@ || mv $@.temp $@
	@rm -f $@.temp

# Create a variable containing a vhdl integer for each var with its value
CONF_VHDL:=$(foreach v,$(CONF_VARS), constant $(v:CONFIG_%=CFG_%) : integer := $(strip ${$v});${\n})
export CONF_VHDL
config/config.vhd: force
	$(info Creating config/config.vhd containing $(foreach v,$(CONF_VARS),${v}=${$v}))
	mkdir -p config
	@echo "-- This file is generated by the makefile" > $@.temp
	@echo "package config is" >>$@.temp
# use two $$ here so that shell translates the CONF_VHDL variable
# and keeps the newlines
	@echo "$$CONF_VHDL" >> $@.temp
	@echo "end;" >>$@.temp
# only replace the file if the new one is different to prevent
# unneeded rebuilding
	@cmp -s $@.temp $@ || mv $@.temp $@
	@rm -f $@.temp


################################################################################
# Pack boot code into memory_fpga.vhd that is SRAM
################################################################################

# force main.srec because ROM_BIN may have changes so timestamp is not
# a reliable indicator of change.
ROM_BIN ?= boot.elf
main.srec: $(ROM_BIN) force
	sh2elf-objcopy -v -O srec --srec-forceS3 $< $@

boot.bin: $(ROM_BIN) force
	sh2elf-objcopy -v -O binary $< $@

ram.dat: main.srec
	$(TOOLS_DIR)/genram/genram-32k $<

memory_fpga.vhd: memory_fpga.vhd.in ram.dat
	perl $(TOOLS_DIR)/patchcode.pl ram.dat > memory_fpga.vhd.temp
# only replace the file if the new one is different to prevent
# unneeded rebuilding
	cmp -s memory_fpga.vhd.temp memory_fpga.vhd || mv memory_fpga.vhd.temp memory_fpga.vhd
	rm -f memory_fpga.vhd.temp

memory_fpga.vhd.in: $(TOOLS_DIR)/memory_fpga.vhd.in
	cp $< $@


################################################################################
# Create file listing vhdl files
################################################################################

$(addprefix ../../,$(VHDL_FILES)): config/config.h

vhdl_list.txt: config/config.vhd $(addprefix ../../,$(VHDL_FILES))
	@echo "Write vhdl_list.txt"
	@echo "$(OUTPUT_DIR)/config/config.vhd" > $@
	@for v in $(addprefix $(TOP_DIR)/,$(VHDL_FILES)); do echo "$$v" >> $@; done

################################################################################
# Run soc_gen
################################################################################

ifeq ($(wildcard $(TOP_DIR)/soc_gen.jar),)

soc_gen:
	@command -v lein || (printf "***************************************************************************\n****** Cannot find lein tool (http://leiningen.org/) nor soc_gen.jar ******\n****** One is required to run the soc_gen tool.                      ******\n***************************************************************************\n" && false)
	(cd $(TOP_DIR)/targets/soc_gen; lein run $(BOARD_NAME))
	@echo "Done"

soc_regen:
	@command -v lein || (printf "***************************************************************************\n****** Cannot find lein tool (http://leiningen.org/) nor soc_gen.jar ******\n****** One is required to run the soc_gen tool.                      ******\n***************************************************************************\n" && false)
	(cd $(TOP_DIR)/targets/soc_gen; lein run -r $(BOARD_NAME))
	@echo "Done"

else

# use packaged soc_gen.jar
soc_gen:
	@echo "Running soc_gen.jar"
	(cd $(TOP_DIR)/targets/soc_gen; java -jar ../../soc_gen.jar $(BOARD_NAME))
	@echo "Done"

soc_regen:
	@echo "Running soc_gen.jar"
	(cd $(TOP_DIR)/targets/soc_gen; java -jar ../../soc_gen.jar -r $(BOARD_NAME))
	@echo "Done"

endif

.PHONY: force soc_gen
