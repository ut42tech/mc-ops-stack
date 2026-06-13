.PHONY: secret setup up down logs restart ps

## Generate the shared forwarding secret (single source of truth). Run once.
secret:
	@mkdir -p secrets
	@if [ -s secrets/forwarding.secret ]; then \
		echo "secrets/forwarding.secret already exists; leaving it untouched."; \
	else \
		openssl rand -hex 24 > secrets/forwarding.secret; \
		echo "Wrote secrets/forwarding.secret"; \
	fi

## Materialize per-server live config from committed *.example templates.
setup:
	@for d in servers/*/config; do \
		if [ -f "$$d/paper-global.yml.example" ] && [ ! -f "$$d/paper-global.yml" ]; then \
			cp "$$d/paper-global.yml.example" "$$d/paper-global.yml"; \
			echo "Created $$d/paper-global.yml"; \
		fi; \
	done
	@[ -f .env ] || cp .env.example .env

up:
	docker compose up -d

down:
	docker compose down

restart:
	docker compose restart

ps:
	docker compose ps

logs:
	docker compose logs -f
