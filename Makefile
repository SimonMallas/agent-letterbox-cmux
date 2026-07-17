.PHONY: test ci

test:
	./tests/smoke.sh
	./tests/test_error_paths.sh
	./tests/cmux-doorbell-safety.sh
	./tests/test_cmux_registration.sh
	./tests/test_cmux_setup.sh

ci: test
