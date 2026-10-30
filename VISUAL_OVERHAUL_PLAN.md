# SOLACE — Plano do Overhaul Visual do Mundo

> Documento vivo. Atualizado a cada marco. Veja também `PROJECT_STATUS.md` (estado atual,
> próximos passos) e `CHANGELOG.md` (o que mudou e quando).

## Fase 0 — Auditoria (2026-10-30)

### Arquitetura atual
- **Godot 4.7.2, Forward+, GDScript.** Cena principal `scenes/main/main.tscn` =
  `Desert` (ambiente) + `Player` + `CameraRig` + `Audio` + `UI`.
- **Tudo é procedural, sem assets externos.** Personagem (SDF), espada (malha facetada),
  capa (cloth em GPU), terreno, céu, sons — tudo gerado em código. O mundo segue essa
  regra: geometria construída em GDScript (`ProcMesh`, `SurfaceTool`), shaders próprios.
- **Ambiente** (`scenes/environment/desert.tscn`):
  - `DuneTerrain` (`scripts/environment/dune_terrain.gd`): função de altura analítica
    `height_at(x, z)` (dunas transversais assimétricas, warp, cristas de lançamento,
    areia solta). Gera malha jogável 512×2,5 m (1280 m de lado) com `HeightMapShape3D`,
    um campo distante de 9 km e paredes de limite. **Todos** (câmera, respawn, efeitos,
    sentinelas) consultam `height_at`, então qualquer mudança de relevo deve passar por ela.
  - `Landmarks` (`scripts/environment/landmarks.gd`): cidade de agulhas distante com feixe
    de luz, arcos de blocos, colunas em torno, toro gigante, pedras "waystone" com faixa de
    luz ciano e o anel "Watchers" em (60, −430).
  - `Sun` (azimute 24°, elevação 9°), `WorldEnvironment` (céu `sky.gdshader`, névoa de
    profundidade + altura, SSAO, glow, tonemap ACES).
- **Jogabilidade que o mundo precisa respeitar:**
  - O `HoverMotor` faz raycasts na máscara 5 (camada 1 = chão, camada 4 = props). Ou seja,
    qualquer corpo estático na camada 1 vira superfície surfável, e a camada 4 é obstáculo
    sólido que a câmera também evita.
  - O respawn acontece se ela ficar 4 m abaixo de `height_at` ou sair da área jogável.
  - As sentinelas de treino ficam em z −32 … −165, |x| < 26 (manter essa faixa livre).
- **Desempenho medido (tour, 1600×900):** 6–10 ms/quadro (~150–190 fps) na RX 6600.
  Sobra muito orçamento para o visual (meta: 60 fps estáveis em 1080p, ≤ 16 ms).

### Problemas visuais atuais
1. **Mundo vazio.** Entre o jogador e o horizonte só há dunas. Falta primeiro plano e
   plano médio: nada de ruínas soterradas, rochas, formações ou lugares memoráveis.
2. **Marcos primitivos.** A cidade de agulhas é um torno de 8 lados em cinza-azulado
   chapado; os arcos são caixas; o toro é um anel liso. Ficam enevoados demais para
   chamar o olhar, e a silhueta não conta história.
3. **Materiais genéricos.** Pedras e ruínas usam `StandardMaterial3D` de cor única. Não
   há estratos, erosão, areia acumulada nem variação.
4. **Paleta da areia avermelhada demais** nas encostas de sombra (fica marrom-tijolo de
   perto); as referências pedem areia dourada-pêssego com sombras frias e violetas.
5. **Céu correto, mas sem massa.** Só cirros finos; faltam bancos de nuvens no horizonte
   que dão escala (referências 2, 3, 4).
6. **Sem vida no ambiente.** Nada se move fora do jogador: sem areia soprando das
   cristas, poeira no ar, tecidos ou água.
7. **Uma única identidade.** Tudo é o mesmo mar de dunas; não há biomas nem áreas
   reconhecíveis.

### O que será reaproveitado
- `DuneTerrain` inteiro: a função de altura ganha "carimbos" para os locais (bacia do
  oásis, platôs das ruínas) sem quebrar colisão nem consultas.
- O shader de areia (ondulações, mosqueado, brilho, areia solta), com paleta e luz
  retocadas.
- O céu, o sol e a névoa, retocados e com névoa volumétrica.
- `ProcMesh` (tornos), `Fx` (partículas), `SandFX` (grãos e poeira do jogador).
- Toda a jogabilidade (movimento, manobras, combate) sem nenhuma alteração.

### O que será reconstruído
- `Landmarks`, substituído por um **construtor de mundo** (`scripts/world/`):
  - kit de ruínas procedural;
  - formações de arenito;
  - sítios compostos à mão;
  - marcos distantes.
- **Materiais de pedra:** shader triplanar de arenito com estratos, erosão e areia
  acumulada nas faces de cima. As ruínas usam a mesma família.
- **Novo:** shader de água e o oásis inundado.
- **Novo:** efeitos de ambiente (areia soprando nas cristas, poeira no ar, cascatas de
  areia, estandartes ao vento, respingos na água, pássaros ao longe).

## Fase 1 — Direção de arte

**Conceito: "As Areias Afundadas".** Um mar de dunas douradas que engoliu a civilização
que forjou a espada do Último Espírito. Tudo o que restou aponta para a luz no horizonte.

| Elemento | Direção |
|---|---|
| Paleta | Areia dourada-pêssego (luz `#F6C68E`, médio `#E9A266`, sombra fria `#B9786A` puxando para o violeta); arenito rosa-laranja com estratos creme; pedra das ruínas creme-acinzentada; acentos turquesa (água, runas — já presentes nas waystones) e âmbar (espada). A capa bordô continua sendo o ponto mais saturado da tela. |
| Luz | Hora dourada. Sol baixo (~13°) e quente, céu azul-pálido no zênite, horizonte pêssego. Sombras longas desenham dunas e colunas. Contraluz quando se olha para o farol. |
| Atmosfera | Névoa em camadas: neblina baixa nos vales, perspectiva aérea forte (o fundo vira silhueta pastel), névoa volumétrica leve com espalhamento do sol (raios entre colunas). Bloom contido. |
| Materiais | Estilizado-pictórico, sem fotorrealismo. Formas grandes legíveis, detalhe de média frequência (estratos, blocos, fissuras), ruído fino só de perto. Nada de texturas repetidas: tudo é triplanar com ruído em várias escalas. |
| Terreno | Dunas esculpidas pelo vento (mantidas), bacias planas onde há ruínas, mesas e escarpas de arenito com estratos nas bordas do mundo. |
| Escala | Primeiro plano 1–5 m (fragmentos, rochas); plano médio 10–60 m (colunatas, arcos, mesas); fundo 100–600 m (Lâmina Caída, cidade das agulhas, muralha de mesas). |

### Composição do primeiro ambiente (área jogável de 1280 m)

Visto do spawn (0, 0), olhando para −Z:
- **Primeiro plano:** dunas, fragmentos de coluna meio enterrados e rochas pequenas.
- **Colunata do Peregrino:** avenida de colunas quebradas e postes de estandarte de
  z −190 a −400, levando às Sentinelas (o anel "Watchers", reformado). Fica fora da faixa
  de treino.
- **Pátio Afogado** (≈ +250, −250): uma bacia com água turquesa e ruínas submersas
  (escadarias, arcos, colunas tombadas). A espada surfa sobre a água, levantando borrifos.
- **Mesas de arenito** com cascatas de areia nas bordas leste e oeste (fora da área de
  surf), dando moldura e escala.
- **Marcos distantes:**
  - **A Lâmina Caída:** uma espada colossal de pedra (o mesmo desenho da espada dela)
    cravada na diagonal numa duna, a ~1 km.
  - **A Cidade das Agulhas** com o farol (refeita com silhueta melhor e menos cinza).
  - **Colosso adormecido:** cabeça gigante semienterrada.

## Fases de implementação (ordem)

| # | Fase | Entregas | Verificação |
|---|---|---|---|
| 1 | Alvo visual | Luz, céu (bancos de nuvens), névoa volumétrica, paleta da areia, grading | Capturas antes/depois dos mesmos pontos |
| 2 | Reconstrução do mundo | Construtor `scripts/world/`, kit de ruínas, arenito, sítios, marcos, carimbos no terreno | Vistas fixas (`--views`), autotest |
| 3 | Materiais | Shader de arenito/pedra, água, ajustes na areia | Vistas fixas de perto |
| 4 | Luz final | Exposição, sombras, ajuste da névoa por área | Vistas + fps |
| 5 | Efeitos e vida | Areia nas cristas, poeira no ar, cascatas de areia, estandartes, respingos e rastro na água, pássaros | Tour + bursts |
| 6 | Câmera | Ajustes leves (sem perder legibilidade) | Tour |
| 7 | Otimização | Faixas de visibilidade, MultiMesh, sombras, contagem de draw calls | fps no tour, autotest, tour de combate |

## Limitações técnicas
- **Blender MCP indisponível nesta sessão** (o handshake do addon falhou). Toda a
  geometria nova é procedural em GDScript, o que combina com o resto do projeto.
  - Se o Blender for conectado depois, o kit de ruínas pode ser refinado lá e exportado
    em glTF para `assets/world/`. Os construtores aceitam trocar a malha.
- **Reflexos na água:** só SSR (Forward+) e o céu. Não há reflexo planar em tempo real
  (caro demais no Godot sem viewport extra).
- **Volumetric fog do Godot** é por frustum. A densidade fica baixa e a distância é
  limitada para manter o custo.
