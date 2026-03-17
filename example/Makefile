SRC_DIR  = .
DIST_DIR = dist
TARGET   = $(DIST_DIR)/MAIN.TOS

CC          = /opt/cross-mintelf/bin/m68k-atari-mintelf-gcc
LIBCMINI    = /opt/cross-mintelf/libcmini

ifneq ($(filter release,$(MAKECMDGOALS)),)
    # --- RELEASE
    CONFIG_NAME = RELEASE (a.out)
    CFLAGS      = -c -std=gnu99 -I$(LIBCMINI)/include -Os -fomit-frame-pointer
    LDFLAGS     = -nostdlib -L$(LIBCMINI)/lib -lcmini -lgcc -lgem -Wl,--traditional-format -s
else
    # --- DEBUG
    CONFIG_NAME = DEBUG (ELF)
    CFLAGS      = -I$(LIBCMINI)/include -std=c99 -g -Wall -fomit-frame-pointer
    LDFLAGS     = -nostdlib -L$(LIBCMINI)/lib -lcmini -lgcc -lgem -Wl,--traditional-format
endif

SRCS = main.c
OBJS = $(patsubst %.c, $(DIST_DIR)/%.o, $(SRCS))

.PHONY: all clean release info prepare

all: prepare info $(TARGET)

release: all

prepare:
	@mkdir -p $(DIST_DIR)

$(TARGET): $(OBJS) 
	$(CC) $(LIBCMINI)/lib/crt0.o $^ $(LDFLAGS) -o $@
	@echo ">>> Build finished: $(TARGET) [$(CONFIG_NAME)]"

$(DIST_DIR)/%.o: %.c | prepare
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -rf $(DIST_DIR)
	@echo "Cleaned."

info:
	@echo "------------------------------------------------"
	@echo " Configuration: $(CONFIG_NAME)"
	@echo " Compiler:      $(CC)"
	@echo " Libcmini:      $(LIBCMINI)"
	@echo "------------------------------------------------"
