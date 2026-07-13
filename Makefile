.PHONY: test ci

test:
	./tests/smoke.sh
	./tests/test_error_paths.sh
	./tests/cmux-doorbell-safety.sh
	./tests/test_desktop_adapter.sh
	./tests/webhook_e2e_harness.sh
	python3 tests/test_skill_prompt.py

ci: test
