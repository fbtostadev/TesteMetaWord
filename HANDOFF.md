# Handoff: fundo e zonas de atmosfera

## Objetivo desta iteração

Na worktree `TesteMetaWord-wt-refactor-bg`, branch `exp/refactor-bg`, substituir os halos sólidos por um campo luminoso contínuo que acompanha as zonas ocupadas. A direção mantém o canvas noturno e o Liquid Glass nativo. A composição orgânica, física, vocabulário e configuração do projeto seguem a base de `main`.

## Estado entregue

- **Foco:** é o resultado da última fusão ou, sem fusão, a palavra com mais combinações. É atraído para o centro do canvas (`Composition.focus`).
- **Zonas:** 1, combina com o foco; 2, combina com outra palavra; 3, sem combinação (`Vocabulary.zone`, `Composition.zones`). Os gaps-alvo até a superfície do foco são 40 / 136 / 232 pt.
- **Atmosfera** (`ContentView.swift`): `EllipticalGradient` com transparência nas duas extremidades, somente nas zonas ocupadas. Zona 1 é a mais luminosa; vazia, deixa o centro neutro. O alcance usa o gap da física + 68 pt; apenas o desenho comprime a largura adicional das frases para 45%. Fundo radial noturno e vinheta além da Zona 3 permanecem independentes da ocupação.
- **Feedback luminoso:** reforço da Zona 1 somente quando o foco participa do ato; luz no ponto médio do par ativo, mais forte ao armar e atenuada pela resistência. Transições de 0,24 s para foco/ocupação/dimensão e 0,14 s para feedback, sem loop. Movimento reduzido elimina a interpolação dos campos. Camada sem interação e oculta da acessibilidade, atrás do vidro.
- **Física** (`Physics.swift`, pura): repulsão abaixo de 40 pt e mola até um slot em cada zona. Os slots têm ângulos uniformes, preservam a ordem angular e usam a rotação de menor deslocamento; o raio é obtido por bisseção no gap-alvo. A física fica congelada durante arrasto, seleção, par preparado e fusão.
- **Fusão:**
  - convergência de 0,2 s;
  - o resultado nasce no ponto de encontro, por crossfade;
  - as sugestões brotam dele com impulsos radiais distintos;
  - o resultado então migra para o centro.
- **Undo:** divide o resultado, que mantém a identidade de vidro, enquanto a outra origem brota. As sugestões somem.
- **Estado armado:** realce branco e pulso a 45% de sobreposição.
- **Flutuação idle:** órbita de 4 pt e 6 s, com fase herdada da origem. A palavra que está sendo manipulada para de flutuar.

## Verificação

- `./scripts/build.sh` aprovado para iPadOS sem assinatura (Xcode 26.4.1).
- Suíte completa no simulador dedicado “TesteMetaWord Atmosphere”, iPad Pro 13-inch (M5), iOS 26.4: 21 testes Swift Testing e 3 XCTest de interface. Resultado em `build/atmosphere-normal-complete.xcresult`.
- Capturas `build/atmosphere-{initial,armed,first-fusion,long-phrase,undo}-normal-complete*.png`; sequências de fusão e Undo em `build/atmosphere-{fusion,split}-normal-complete-*.png`. Inspeção do estado inicial, par armado durante pressão, frase longa com Zona 1 vazia e retorno pelo Undo. Sem degraus perceptíveis e sem emenda entre canvas e barras.
- Automação da soltura superficial estabilizada com medidas lidas uma vez e destino ancorado no canvas.
- Teste de interface ampliado: três fusões por arrasto até “Eu quero comer agora”, Undo e capturas anexadas. `scripts/capture-atmosphere.py` executa os testes num UDID explícito, captura o arrasto mantido por XCTest via `simctl` e exporta os anexos para `build/`.

## Pendências

- Avaliação manual da sensação do gesto e da física, do idle em uso de C.A., da membrana, do long press, do VoiceOver, do desempenho; iPad físico.
- Fora desta iteração:
  - tint/fundo do vidro;
  - hierarquia visual da frase;
  - membrana em rubber band;
  - glifo do Undo;
  - ordem espacial do VoiceOver.
- Motor de IA local: seam pronto no app (`CompositionEngine`, `RuleEngine`, `Composition.refresh()`), workspace `ml/` com dataset, LoRA e avaliação. Próximo: revisar `ml/vocabulary.json`, treinar a sério, fundir/quantizar e implementar `LocalModelEngine` com MLX Swift (validar em iPad físico).
