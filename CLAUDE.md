# RifaApp — notas para agentes IA

- **Antes de tocar el VPS, nginx, Docker, DNS o desplegar: lee [docs/INFRAESTRUCTURA_VPS.md](docs/INFRAESTRUCTURA_VPS.md).**
  Producción y los entornos de clientes comparten servidor; un error puede tumbar a todos.
- Nunca escribas credenciales (SSH, tokens, claves) en el repo, docs o commits.
- Un `git push` a `master` redespliega producción automáticamente. No hagas push/commit sin que el usuario lo pida.
- Stack: Flutter (web/android) en `lib/`, backend Node/Express en `backend/server.js`, WhatsApp vía Evolution API.
- Flutter está en `~/development/flutter/bin` (no está en el PATH): `export PATH=$HOME/development/flutter/bin:$PATH` antes de `flutter analyze` / `flutter build web --release`.
- **Multi-empresa: cada asesor pertenece a UNA sola empresa.** Nunca asignes, muestres ni autorices a un asesor en una rifa o boleta de otra empresa (ver `advisorBelongsToCompany` y `repairCrossCompanyAdvisors` en `backend/server.js`). Toda consulta o cambio debe filtrarse por la empresa del usuario.
