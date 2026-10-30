# SOLACE — Estado do Projeto

Última atualização: 2026-10-30 (overhaul visual do mundo, rodada 1).

## Onde estamos

O primeiro ambiente, **"As Areias Afundadas"**, foi reconstruído. Está jogável, sem erros de
script, e o autotest passa. Fases do `VISUAL_OVERHAUL_PLAN.md`:

| Fase | Estado |
|---|---|
| 0 Auditoria | ✅ Feita (no plano) |
| 1 Alvo visual | ✅ Luz, céu, névoa e paleta definidos |
| 2 Reconstrução do mundo | ✅ Sítios, marcos e mesas construídos |
| 3 Materiais | ✅ Pedra/arenito, água, areia molhada, folhagem e estandartes. Melhorias abertas abaixo |
| 4 Luz | ✅ Primeiro passe (névoa volumétrica leve, grading) |
| 5 Efeitos e vida | ✅ Areia soprando nas cristas, poeira no ar, estandartes, cascatas de areia, pássaros, borrifos na água |
| 6 Câmera | ⏳ Não mexida (a câmera de jogo já evita props e terreno) |
| 7 Otimização | ⏳ Medido (≈ 5 ms/quadro nas vistas fixas); falta LOD e faixas de visibilidade |

## Como o mundo é montado (para retomar o trabalho)

- `scripts/world/world_layout.gd` (`WorldLayout`): **fonte única** das posições de todos os
  sítios. O terreno (`DuneTerrain.height_at`) usa essas posições para moldar o chão:
  - a bacia do oásis (margem irregular, `water_level` calculado);
  - a avenida da colunata;
  - o caminho calmo do início até o arco.
- `scripts/world/world_builder.gd` (`WorldBuilder`, nó `Desert/World`): constrói os sítios.
  - Cada sítio é **uma malha mesclada por material** (uma draw call), com colisões
    simples na camada 4.
  - Constrói: colunata e arco, Sentinelas (Watchers), Pátio Afogado (aqueduto, escadaria,
    colunas, muro, água), mesas próximas (sólidas) e distantes, rochas, fragmentos perto
    do início, a Lâmina Caída, o Guardião Adormecido, o aqueduto colossal e as colunas
    gigantes no horizonte.
- `scripts/world/mesh_kit.gd` (`MeshKit`): acumula geometria e grava nas cores de vértice
  R = cavidade, G = borda gasta, B = altura acima da areia (a areia sobe no pé das peças).
- `scripts/world/stone_kit.gd` (`StoneKit`): peças:
  - coluna canelada (inteira ou quebrada) e tambor caído;
  - arco de aduelas, escadaria e muro;
  - monólito;
  - mesa e cluster de mesas.
- `scripts/world/water_surface.gd` (`WaterSurface`): disco d'água com shader e corpo de
  colisão na camada 1 (**ela surfa na água**; o `SandFX` troca areia por borrifos ali).
- `scripts/world/flora.gd` (`Flora`): palmeiras (merge) e juncos (MultiMesh) em volta do oásis.
- `scripts/world/ambience_fx.gd` (`AmbienceFX`): areia nas cristas (varredura de 1 linha
  por quadro), poeira, estandartes, cascatas de areia (raycast nas mesas) e pássaros.
- **Shaders novos:** `stone`, `water`, `foliage`, `banner`, `sandfall` e `bird`
  (`.gdshader`). O `sand.gdshader` ganhou areia molhada (`water_zone`) e grão suave, sem
  quadriculado. O `sky.gdshader` ganhou bancos de nuvens no horizonte.
- `scripts/environment/landmarks.gd` agora só faz a Cidade das Agulhas e o farol.

## Como verificar

- **Vistas fixas do mundo:** `Godot --path . -- --views --out=<pasta> [--only=01_spawn_ahead,04_oasis]`.
  São 16 pontos de vista definidos em `scripts/debug/world_views.gd`.
- **Testes de jogo:**
  - `-- --autotest` (headless);
  - `-- --tour`;
  - `-- --tour --combat`;
  - `-- --tour --start=150,-240,-1.5708` (surf atravessando o oásis).
- **Classes novas (`class_name`):** rode antes `Godot --headless --path . --import` para
  atualizar o cache de classes.

## Problemas conhecidos / próximos passos

1. **Cascatas de areia:** legíveis, mas ainda finas. Uma fita única não basta: faltam várias
   fitas, poeira maior na base e talvez partículas caindo.
2. **Mesas próximas de perto:** têm cara de "torres derretidas" (o tubo com ruído). Ideias:
   - talhar faces planas (quantizar o ângulo);
   - usar mais satélites e blocos caídos na base.
3. **Água:**
   - sem reflexo real (só céu por Fresnel);
   - margem cortada pelo disco (`radius`) quando a areia em volta é baixa;
   - não há ondulações nem rastro na superfície causados pela espada (só partículas).
4. **Bioma 2:** o oásis é o embrião das "ruínas inundadas". Falta uma área maior
   (escadarias submersas, templo, vegetação densa).
5. **Câmera cênica (fase 6) e LOD/faixas de visibilidade (fase 7).**
6. **Neblina:** o lado do sol ainda fica leitoso em ângulo baixo. Ajustar
   `fog_sun_scatter`, a névoa volumétrica e o grading por hora do dia.
7. **Blender MCP não conectou nesta sessão.** Se conectar, é possível refinar o kit de
   ruínas (estátuas, capitéis esculpidos) e exportar glTF para `assets/world/`.

## Próxima ação exata

Abrir o jogo, rodar até o oásis e pela colunata e anotar o que incomoda. Em seguida:
1. melhorar as cascatas de areia e as mesas próximas (itens 1 e 2);
2. adicionar ondulações/rastro na água;
3. passar para a fase 7 (faixas de visibilidade nos sítios distantes).
