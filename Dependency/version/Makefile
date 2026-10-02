ALL: version.h

# Regenerated on every build so the macdown command line tool reports the
# current version. The script only rewrites version.h when it changes.
version.h: FORCE
	bash ../../Tools/generate_version_header.sh

FORCE:

.PHONY: install clean distclean FORCE

install: ALL

clean:
	-rm version.h 2>/dev/null

distclean: clean
