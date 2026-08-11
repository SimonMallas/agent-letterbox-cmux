.PHONY: test ci

test:
	./tests/smoke.sh
	./tests/test_error_paths.sh
	./tests/test_lifecycle_v02.sh
	./tests/test_cmux_registration.sh
	./tests/test_cmux_setup.sh
	./tests/cmux-doorbell-safety.sh

ci: test
