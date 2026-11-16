.PHONY: stats

stats:
	@printf "%-10s %8s %10s %10s\n" "Category" "Files" "Lines" "Words"
	@for cat in "not-test:/test/" "is-test:^/test/"; do \
		name=$${cat%%:*}; \
		pattern=$${cat#*:}; \
		if [ "$$name" = "not-test" ]; then \
			filter='grep -v /tests*/'; \
		else \
			filter='grep /tests*/'; \
		fi; \
		files=$$(find .. -name '*.dart' | eval $$filter | wc -l); \
		counts=$$(find .. -name '*.dart' | eval $$filter | xargs wc -lw | grep total | awk '{print $$1, $$2}'); \
		lines=$$(echo $$counts | awk '{print $$1}'); \
		words=$$(echo $$counts | awk '{print $$2}'); \
		printf "%-10s %8d %10d %10d\n" "$$name" "$$files" "$$lines" "$$words"; \
	done
