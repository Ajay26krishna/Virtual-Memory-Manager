CC = gcc
CPPFLAGS = -I.
CFLAGS = -Wall -std=gnu17 -D_GNU_SOURCE
LDFLAGS = -L.
LDLIBS = -pthread -lm
export CC CPPFLAGS CFLAGS LDFLAGS LDLIBS

SUBDIRS = libmemmanager
.PHONY: default debug clean $(SUBDIRS)

default: tester

debug: export CFLAGS += -g
debug: default

$(SUBDIRS):
	$(MAKE) -C $@

tester: main.c libmemmanager
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ main.c -Ilibmemmanager -Llibmemmanager -lmemmanager $(LDFLAGS) $(LDLIBS)

clean:
	rm -rf tester output
	@for d in $(SUBDIRS); do $(MAKE) -C $$d clean; done
