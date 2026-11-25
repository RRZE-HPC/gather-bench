#CONFIGURE BUILD SYSTEM
OP_SUFFIX  = $(if $(filter-out gather,$(strip $(OP))),-$(strip $(OP)))
TARGET	   = gather-bench-$(TAG)$(OP_SUFFIX)
BUILD_DIR  = ./build/$(TAG)-$(ISA)$(OP_SUFFIX)
SRC_DIR	= ./src
MAKE_DIR   = ./make
ifeq ($(strip $(ISA)),sve)
ISA_DIR	= ./src/sve2
else
ISA_DIR	= ./src/x86-64/$(ISA)
endif
Q		 ?= @

#DO NOT EDIT BELOW
include ./config.mk
include $(MAKE_DIR)/include_$(TAG).mk
include $(MAKE_DIR)/include_LIKWID.mk
INCLUDES  += -I./src/includes

VPATH	 = $(SRC_DIR) ${ISA_DIR}
ASM	   = $(patsubst $(SRC_DIR)/%.c, $(BUILD_DIR)/%.s,$(wildcard $(SRC_DIR)/*.c))
ASM	  += $(patsubst $(SRC_DIR)/%.f90, $(BUILD_DIR)/%.s,$(wildcard $(SRC_DIR)/*.f90))
OBJ	   = $(filter-out $(BUILD_DIR)/main%, $(patsubst $(SRC_DIR)/%.c, $(BUILD_DIR)/%.o,$(wildcard $(SRC_DIR)/*.c)))
OBJ	  += $(patsubst $(SRC_DIR)/%.cc, $(BUILD_DIR)/%.o,$(wildcard $(SRC_DIR)/*.cc))
OBJ	  += $(patsubst $(SRC_DIR)/%.cpp, $(BUILD_DIR)/%.o,$(wildcard $(SRC_DIR)/*.cpp))
OBJ	  += $(patsubst $(SRC_DIR)/%.f90, $(BUILD_DIR)/%.o,$(wildcard $(SRC_DIR)/*.f90))
OBJ	  += $(patsubst $(SRC_DIR)/%.F90, $(BUILD_DIR)/%.o,$(wildcard $(SRC_DIR)/*.F90))
OBJ	  += $(patsubst $(SRC_DIR)/%.s, $(BUILD_DIR)/%.o,$(wildcard $(SRC_DIR)/*.s))
OBJ	  += $(patsubst $(ISA_DIR)/%.S, $(BUILD_DIR)/%.o,$(wildcard $(ISA_DIR)/*.S))
CPPFLAGS := $(CPPFLAGS) $(DEFINES) $(INCLUDES) -DISA_$(ISA)

ifneq ($(VARIANT),)
	.DEFAULT_GOAL := ${TARGET}-$(VARIANT)
endif

ifeq ($(strip $(DATA_LAYOUT)),AOS)
    CPPFLAGS += -DAOS
endif

ifeq ($(strip $(TEST)),true)
    CPPFLAGS += -DTEST
endif

ifeq ($(strip $(PADDING)),true)
    CPPFLAGS += -DPADDING
endif

ifeq ($(strip $(MEASURE_GATHER_CYCLES)),true)
    CPPFLAGS += -DMEASURE_GATHER_CYCLES
endif

ifeq ($(strip $(ONLY_FIRST_DIMENSION)),true)
    CPPFLAGS += -DONLY_FIRST_DIMENSION
endif

ifeq ($(strip $(MEM_TRACER)),true)
    CPPFLAGS += -DMEM_TRACER
endif

ifeq ($(strip $(DATA_TYPE)),SP)
    CPPFLAGS += -DDATA_TYPE_SP
    ifeq ($(strip $(KERNEL)),asm)
        ifeq ($(strip $(VARIANT)),md-trace)
            $(error DATA_TYPE=SP is not supported for the md-trace variant; its kernels remain double-precision only)
        endif
    endif
endif

# UNROLL is honored by both kernels for main.c/main-md.c (gather/gather_aos/gather_soa);
# the md-trace kernels (gather_md_aos/gather_md_soa) still have a fixed unroll factor.
CPPFLAGS += -DUNROLL=$(UNROLL)
ifeq ($(strip $(VARIANT)),md-trace)
    ifneq ($(strip $(UNROLL)),4)
        $(warning UNROLL is not honored by the md-trace variant; its kernels have a fixed unroll factor)
    endif
endif

ifeq ($(strip $(OP)),scatter)
    CPPFLAGS += -DOP_SCATTER
else ifeq ($(strip $(OP)),rmw)
    CPPFLAGS += -DOP_RMW
else ifneq ($(strip $(OP)),gather)
    $(error Invalid OP: $(OP). Must be one of: gather, scatter, rmw)
endif
ifneq ($(strip $(OP)),gather)
    ifneq ($(strip $(KERNEL)),intrinsic)
        $(error OP=$(OP) requires KERNEL=intrinsic)
    endif
endif

ifeq ($(strip $(KERNEL)),intrinsic)
    CPPFLAGS += -DKERNEL_INTRINSIC
    ifeq ($(strip $(PADDING)),true)
        $(error PADDING is not supported by KERNEL=intrinsic)
    endif
    ifeq ($(strip $(ONLY_FIRST_DIMENSION)),true)
        $(error ONLY_FIRST_DIMENSION is not supported by KERNEL=intrinsic)
    endif
    ifeq ($(strip $(MEASURE_GATHER_CYCLES)),true)
        $(error MEASURE_GATHER_CYCLES is not supported by KERNEL=intrinsic)
    endif
    ifeq ($(strip $(MEM_TRACER)),true)
        $(error MEM_TRACER is not supported by KERNEL=intrinsic)
    endif
endif

FLAGS_STAMP = $(BUILD_DIR)/.flags
# Binaries are named by TAG/OP/VARIANT only, so a link stamp per binary name
# forces a relink when the same name is built from another ISA/KERNEL/... config.
LINK_STAMP  = ./build/.link-
LINK_FLAGS  = $(BUILD_DIR) $(BUILD_FLAGS) $(LINKER) $(LFLAGS) $(LIBS)
BUILD_FLAGS = $(CC) $(CXX) $(CPPFLAGS) $(CFLAGS) $(CXXFLAGS) $(ASFLAGS)

${TARGET}: $(OBJ) $(SRC_DIR)/main.c $(LINK_STAMP)$(TARGET)
	@echo "===>  LINKING  $(TARGET)"
	$(Q)${LINKER} ${CPPFLAGS} ${LFLAGS} -o $(TARGET) $(SRC_DIR)/main.c $(OBJ) $(LIBS)

${TARGET}-%: $(OBJ) $(SRC_DIR)/main-%.c $(LINK_STAMP)$(TARGET)-%
	@echo "===>  LINKING  $(TARGET)-$* "
	$(Q)${LINKER} ${CPPFLAGS} ${LFLAGS} -o $(TARGET)-$* $(SRC_DIR)/main-$*.c $(OBJ) $(LIBS)

asm: $(ASM)

$(BUILD_DIR)/%.o: %.c $(FLAGS_STAMP) | $(BUILD_DIR)
	@echo "===>  COMPILE  $@"
	$(Q)$(CC) -c $(CPPFLAGS) $(CFLAGS) $< -o $@
	$(Q)$(CC) $(CPPFLAGS) -MT $(@:.d=.o) -MM  $< > $(BUILD_DIR)/$*.d

$(BUILD_DIR)/%.s: %.c $(FLAGS_STAMP) | $(BUILD_DIR)
	@echo "===>  GENERATE ASM  $@"
	$(Q)$(CC) -S $(CPPFLAGS) $(CFLAGS) $< -o $@

$(BUILD_DIR)/%.s: %.f90 $(FLAGS_STAMP) | $(BUILD_DIR)
	@echo "===>  COMPILE  $@"
	$(Q)$(FC) -S  $(FCFLAGS) $< -o $@

$(BUILD_DIR)/%.o: %.cc $(FLAGS_STAMP) | $(BUILD_DIR)
	@echo "===>  COMPILE  $@"
	$(Q)$(CXX) -c $(CPPFLAGS) $(CXXFLAGS) $< -o $@
	$(Q)$(CXX) $(CPPFLAGS) -MT $(@:.d=.o) -MM  $< > $(BUILD_DIR)/$*.d

$(BUILD_DIR)/%.o: %.cpp $(FLAGS_STAMP) | $(BUILD_DIR)
	@echo "===>  COMPILE  $@"
	$(Q)$(CXX) -c $(CPPFLAGS) $(CXXFLAGS) $< -o $@
	$(Q)$(CXX) $(CPPFLAGS) -MT $(@:.d=.o) -MM  $< > $(BUILD_DIR)/$*.d

$(BUILD_DIR)/%.o: %.f90 $(FLAGS_STAMP) | $(BUILD_DIR)
	@echo "===>  COMPILE  $@"
	$(Q)$(FC) -c  $(FCFLAGS) $< -o $@

$(BUILD_DIR)/%.o: %.F90 $(FLAGS_STAMP) | $(BUILD_DIR)
	@echo "===>  COMPILE  $@"
	$(Q)$(FC) -c  $(CPPFLAGS)  $(FCFLAGS) $< -o $@

$(BUILD_DIR)/%.o: %.s $(FLAGS_STAMP) | $(BUILD_DIR)
	@echo "===>  ASSEMBLE  $@"
	$(Q)$(AS)  $(ASFLAGS) $< -o $@

$(BUILD_DIR)/%.o: %.S $(FLAGS_STAMP) | $(BUILD_DIR)
	@echo "===>  ASSEMBLE  $@"
	$(Q)$(CC) -c $(CPPFLAGS) $< -o $@

tags:
	@echo "===>  GENERATE  TAGS"
	$(Q)ctags -R


$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

# Objects in BUILD_DIR are shared between KERNEL/DATA_TYPE/UNROLL/... settings,
# so record the effective flags and force a rebuild whenever they change;
# otherwise stale objects get silently linked against a freshly built main.
$(FLAGS_STAMP): FORCE | $(BUILD_DIR)
	@echo '$(BUILD_FLAGS)' | cmp -s - $@ || echo '$(BUILD_FLAGS)' > $@

$(LINK_STAMP)%: FORCE | $(BUILD_DIR)
	@echo '$(LINK_FLAGS)' | cmp -s - $@ || echo '$(LINK_FLAGS)' > $@

ifeq ($(findstring $(MAKECMDGOALS),clean),)
-include $(OBJ:.o=.d)
endif

.PHONY: clean distclean asm tags FORCE
.PRECIOUS: $(LINK_STAMP)%
FORCE:

clean:
	@echo "===>  CLEAN"
	@rm -rf $(BUILD_DIR)
	@rm -f tags

distclean: clean
	@echo "===>  DIST CLEAN"
	@rm -f $(TARGET)
	@rm -f tags
