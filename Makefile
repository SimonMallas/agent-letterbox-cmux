.PHONY: test ci

# Run a lifecycle suite and require its final PASS footer (guards set -e early abort).
define run_lifecycle
	@out=$$(mktemp); \
	if ./$(1) >"$$out" 2>&1; then rc=0; else rc=$$?; fi; \
	cat "$$out"; \
	if ! grep -qF '$(2)' "$$out"; then \
	  echo "FAIL: $(1) missing required footer: $(2) (rc=$$rc)" >&2; \
	  rm -f "$$out"; \
	  exit 1; \
	fi; \
	rm -f "$$out"; \
	exit $$rc
endef

test:
	./tests/smoke.sh
	./tests/test_error_paths.sh
	./tests/test_no_private_data.sh
	./tests/test_no_private_vocabulary.sh
	./tests/test_release_text.sh
	$(call run_lifecycle,tests/test_lifecycle_v02.sh,lifecycle v0.2: PASS)
	$(call run_lifecycle,tests/test_lifecycle_v03.sh,lifecycle v0.3: PASS)
	./tests/test_lifecycle_early_abort_mutation.sh
	./tests/test_cmux_registration.sh
	./tests/test_cmux_setup.sh
	./tests/cmux-doorbell-safety.sh

ci: test
