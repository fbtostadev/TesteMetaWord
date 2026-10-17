# Handoff — composição orgânica com centro óptico e zonas

## Objetivo desta iteração

Trocar a grade brick-wall rígida por uma composição orgânica: centro óptico (foco), três zonas de atmosfera por relevância, física que só reorganiza fora do gesto, mitose na fusão e flutuação idle sincronizada por família.

## Estado entregue

- **Foco:** é o resultado da última fusão ou, sem fusão, a palavra com mais combinações. É atraído para o centro do canvas (`Composition.focus`).
- **Zonas:** 1, combina com o foco; 2, combina com outra palavra; 3, sem combinação (`Vocabulary.zone`, `Composition.zones`). Os gaps-alvo até a superfície do foco são 40 / 136 / 232 pt. Três halos sutis desenham as atmosferas.
- **Física** (`Physics.swift`, pura): repulsão abaixo de 40 pt e mola até um slot em cada zona. Os slots têm ângulos uniformes, preservam a ordem angular e usam a rotação de menor deslocamento; o raio é obtido por bisseção no gap-alvo. A física fica congelada durante arrasto, seleção, par preparado e fusão.
- **Fusão:**
  - convergência de 0,2 s;
  - o resultado nasce no ponto de encontro, por crossfade;
  - as sugestões brotam dele com impulsos radiais distintos;
  - o resultado então migra para o centro.
- **Undo:** divide o resultado, que mantém a identidade de vidro, enquanto a outra origem brota. As sugestões somem.
- **Removidos:**
  - o dwell e seus parâmetros de calibração;
  - a reordenação, o `BrickLayout` e o `pinPair`;
  - o vínculo de 8 pt do par por toque;
  - o afastamento de incompatíveis durante o arrasto.
- **Estado armado:** realce branco e pulso a 45% de sobreposição.
- **Flutuação idle:** órbita de 4 pt e 6 s, com fase herdada da origem. A palavra que está sendo manipulada para de flutuar.

## Verificação

- `./scripts/build.sh` aprovado.
- `xcodebuild test` (comando do README): 19 testes Swift Testing e 2 XCTest de interface aprovados no iPad Pro 13-inch (M5), iOS 26.4.
- Capturas no simulador: `docs/media/zones-initial.png`, `docs/media/zones-fusion-frames.png`, `docs/media/zones-after-fusion.png`.

## Pendências

- Avaliação manual da sensação do gesto e da física, do idle em uso de C.A., da membrana, do long press, do VoiceOver, do movimento reduzido e do desempenho; iPad físico.
- Fora desta iteração:
  - tint/fundo do vidro;
  - hierarquia visual da frase;
  - membrana em rubber band;
  - glifo do Undo;
  - ordem espacial do VoiceOver.
- Motor de IA local: seam pronto no app (`CompositionEngine`, `RuleEngine`, `Composition.refresh()`), workspace `ml/` com dataset, LoRA e avaliação. Próximo: revisar `ml/vocabulary.json`, treinar a sério, fundir/quantizar e implementar `LocalModelEngine` com MLX Swift (validar em iPad físico).
- Prospecção de longo prazo (vocabulário aberto, dados, treino, avaliação e outros idiomas): [future-HANDOFF.md](future-HANDOFF.md).
