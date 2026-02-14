# TODO - DroneApp Refactor (REST + JWT RS256)

## Steps
- [x] 8. Plan: Docker-only setup, new gitignore, remove obsolete backend, validate services
- [x] 9. Add Dockerfiles for each service + docker-compose with one command
- [x] 10. Rewrite .gitignore
- [x] 11. Remove obsolete backend folder and update README for Docker usage
- [ ] 12. Run tests/health checks for all services; fix issues
  - Blocked: Docker engine not responding (500 on _ping).
- [x] 0. Create this TODO checklist and keep it updated after each step
- [x] 1. Split services: Order API, Tracking Service, Drone Simulator (separate folders)
- [x] 2. Define REST contracts between services and adjust code paths
- [x] 3. Implement JWT RS256 access+refresh and enforce on REST/WS
- [x] 4. Remove auto-start simulation on tracking; enforce explicit start flow
- [x] 5. Update Flutter client for new endpoints and auth headers
- [x] 6. Remove external API docs (Documentation.md, openapi.yaml)
- [x] 7. Update README for new architecture and run instructions
