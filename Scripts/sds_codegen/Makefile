REPO_ROOT=../../

default: parse_and_regenerate

parse_and_regenerate:
	cd $(REPO_ROOT) && \
		Scripts/sds_codegen/sds_codegen.sh

regen: regenerate
regenerate:
	cd $(REPO_ROOT) && \
		Scripts/sds_codegen/sds_regenerate.sh

clean:
	find $(REPO_ROOT) -name \*.sdsjson -exec rm {} \;
