# Changelog

## 2026-10-30 — Overhaul visual do mundo, rodada 1 ("As Areias Afundadas")

Backup antes das mudanças: `Desktop/GAME_backups/2026-10-30_before_world_overhaul`.

### Mundo
- **Construtor de mundo procedural** (`scripts/world/`):
  - `WorldLayout` é a fonte única das posições;
  - `WorldBuilder` constrói os sítios;
  - `MeshKit` e `StoneKit` dão a geometria (colunas caneladas, arcos de aduelas, escadas,
    muros, monólitos, mesas em cluster com estratos, taludes e ravinas);
  - uma malha mesclada por sítio.
- **Sítios:**
  - Colunata do Peregrino, com arco de entrada, colunas quebradas, tambores caídos e uma
    plataforma em degraus;
  - Sentinelas (anel de monólitos com faixa de luz e altar);
  - Pátio Afogado (oásis com água turquesa, aqueduto de 4 arcos, um deles desabado,
    escadaria descendo na água, colunas no raso, muro quebrado, palmeiras e juncos);
  - 5 mesas sólidas na área jogável, 8 mesas distantes e rochas;
  - fragmentos meio enterrados perto do início.
- **Marcos distantes:**
  - a Lâmina Caída: espada de pedra de 260 m cravada na diagonal, no desenho da espada dela;
  - o Guardião Adormecido: capuz colossal semienterrado com a estrela âmbar;
  - um aqueduto colossal e colunas gigantes no horizonte.
- **Terreno** (`DuneTerrain.height_at`):
  - bacia do oásis com margem irregular;
  - avenida acalmada;
  - caminho do início até o arco (que aparece logo na primeira visão).
- **Removidos:** as pedras próximas antigas e os anéis e arcos de caixas no horizonte de
  `Landmarks`. Ficou só a Cidade das Agulhas.

### Materiais
- `stone.gdshader`: pedra pintada em espaço de mundo.
  - Dois modos: estratos de arenito e alvenaria com juntas.
  - Erosão e areia acumulada no topo e no pé (pela cor de vértice).
  - Paletas: arenito rosa-laranja e calcário ocre.
- `water.gdshader`:
  - refração com profundidade vertical (raso turquesa, fundo azul-petróleo);
  - espuma na margem, céu por Fresnel e caminho de brilho do sol.
- **Areia:**
  - paleta dourada-pêssego com sombras frias;
  - **grão suave** (o grão em células quadradas aparecia como pixels);
  - areia molhada e brilhante na margem do oásis.
- `foliage.gdshader` (troncos, frondes com folíolos recortados, juncos; vento),
  `banner.gdshader`, `sandfall.gdshader` e `bird.gdshader`.

### Luz e atmosfera
- **Sol:** 9° → 13° de elevação, cor mais dourada.
- **Névoa:** volumétrica leve (raios de luz), espalhamento do sol reduzido e névoa
  de profundidade e perspectiva aérea mais claras.
- **Céu:** mais azul, com bancos de cúmulos suaves no horizonte.
- **Grading:** contraste 1,12, saturação 1,1.

### Vida e efeitos
- **Ambiente:**
  - areia soprando das cristas ao redor da câmera;
  - poeira dourada no ar;
  - estandartes tremulando na colunata;
  - cascatas de areia nas mesas;
  - 3 bandos de pássaros.
- **Água jogável:** ela surfa no oásis e o `SandFX` emite borrifos, rastro e névoa
  d'água em vez de areia.

### Ferramentas e testes
- `-- --views`: vistas fixas do mundo para comparação (`scripts/debug/world_views.gd`).
- **Autotest:** a checagem "colisão vs. altura analítica" ignora a água, que também é
  surfável.
