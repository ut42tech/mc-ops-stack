.PHONY: secret setup up down logs restart ps

## Generate the shared forwarding + RCON secrets (single source of truth). Run once.
secret:
	@mkdir -p secrets
	@for f in forwarding.secret rcon.secret; do \
		if [ -s secrets/$$f ]; then \
			echo "secrets/$$f already exists; leaving it untouched."; \
		else \
			openssl rand -hex 24 > secrets/$$f; \
			echo "Wrote secrets/$$f"; \
		fi; \
	done

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
