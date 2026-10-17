# Handoff: atmosfera reativa com Metal

## Objetivo desta iteração

Na worktree `TesteMetaWord-wt-metal-atmosphere`, branch `exp/metal-atmosphere`, comparar um shader de luz procedural com o fundo por gradientes. A referência foi preservada no commit `6543743`, integrado a `main` em `4a286ee`. O objetivo é continuidade visual sutil durante o gesto; a avaliação desta etapa usa o simulador.

## Estado entregue

- **Foco:** é o resultado da última fusão ou, sem fusão, a palavra com mais combinações. É atraído para o centro do canvas (`Composition.focus`).
- **Zonas:** 1, combina com o foco; 2, combina com outra palavra; 3, sem combinação (`Vocabulary.zone`, `Composition.zones`). Os gaps-alvo até a superfície do foco são 40 / 136 / 232 pt.
- **Referência por gradientes** (`AtmosphereView.swift`): `EllipticalGradient` com transparência nas duas extremidades, somente nas zonas ocupadas. Zona 1 é a mais luminosa; vazia, deixa o centro neutro. O alcance usa o gap da física + 68 pt; apenas o desenho comprime a largura adicional das frases para 45%. Fundo radial noturno e vinheta além da Zona 3 permanecem independentes da ocupação.
- **Metal** (`Atmosphere.metal`): shader `[[ stitchable ]]` como `ShapeStyle`, com dithering, alfa pré-multiplicado e teto de 0,18. Três zonas analíticas usam gaps recebidos da física. O par usa distância a cápsulas e união suave (24 pt), queda de 28 pt e deformação local de até 8 pt num alcance de 160 pt.
- **Dados compartilhados:** foco, três intensidades, duas superfícies visíveis e aproximação lógica. A resistência atenua a luz e o recuo da membrana desloca a geometria. Não há buffer do vocabulário, relógio adicional ou efeito sobre o texto/vidro.
- **Comparação:** menu nativo Metal/Gradientes na calibração, sem persistência nem reset da composição/Undo. Metal é o padrão. Pré-compilação assíncrona; Gradientes enquanto prepara ou se falhar, com estado visível no painel. O relógio do canvas pausa enquanto o painel está aberto; o popover é ancorado no botão de calibração.
- **Feedback luminoso:** reforço interno somente se o foco participar, par mais luminoso ao armar e atenuado pela resistência. Interpolação de foco/ocupação/dimensão em 0,24 s e feedback em 0,14 s; última geometria retida durante a saída. Camada sem interação, atrás do vidro. Sem animação autônoma.
- **Física** (`Physics.swift`, pura): repulsão abaixo de 40 pt e mola até um slot em cada zona. Os slots têm ângulos uniformes, preservam a ordem angular e usam a rotação de menor deslocamento; o raio é obtido por bisseção no gap-alvo. A física fica congelada durante calibração, arrasto, seleção, par preparado e fusão.
- **Fusão:**
  - convergência de 0,2 s;
  - o resultado nasce no ponto de encontro, por crossfade;
  - as sugestões brotam dele com impulsos radiais distintos;
  - o resultado então migra para o centro.
- **Undo:** divide o resultado, que mantém a identidade de vidro, enquanto a outra origem brota. As sugestões somem.
- **Tensão do long press** (`SplitTension.swift`, integrado de `exp/long-press-split`): durante os 0,6 s da pressão no resultado da última fusão, a bolha treme (até 2,5 pt, progresso²) e incha até 1,04×, e um som tremular sintetizado cresce. Na divisão, um estalo de ~90 ms. Desistir esmaece o som em ~40 ms, sem estalo. Palavra indivisível: nada acontece. Áudio ambiente (respeita o modo silencioso); o iPad não tem háptico para o dedo, então o som faz esse papel.
- **Pinça** (`TouchTracker.swift`, integrado de `exp/pinca`): um dedo repousado em cada uma de duas bolhas seleciona o par; cada bolha segue o seu dedo, 45% arma e soltar o primeiro dedo armado confirma. Par incompatível só resiste. Terceiro dedo ignorado; dois dedos bloqueiam a divisão por long press. Pinça e tensão do long press conferidas à mão no simulador; falta iPad físico.
- **Estado armado:** realce branco e pulso a 45% de sobreposição.
- **Flutuação idle:** órbita de 4 pt e 6 s, com fase herdada da origem. A palavra que está sendo manipulada para de flutuar.

## Verificação

- Referência: build aprovado, 21 testes de lógica e 3 de interface no commit `6543743`; capturas versionadas em `docs/media/atmosphere-{initial,armed,first-fusion,long-phrase,undo}.jpg`.
- O teste visual executa três arrastos e Undo em cada renderizador; confirma Metal ativo, compara modos na mesma sessão e captura rotação com frase longa. A soltura superficial inclui pressão mantida para observar resistência.
- `scripts/capture-atmosphere.py` executa em UDID explícito e exporta capturas com modo e label em `build/`, incluindo o gesto armado enquanto XCTest mantém a pressão.

- Build final para iPadOS aprovado. Suíte completa: 23 testes de lógica + 5 de interface em `build/atmosphere-compare-final.xcresult`. Os 5 testes de interface passaram também com a captura armada refinada em `build/atmosphere-verified.xcresult`.
- Percurso Metal com rotação aprovado em `build/atmosphere-rotation.xcresult`; capturas de tela inteira corrigem o recorte de retrato do snapshot do app. Comparação visual, estado armado parcial, resistência, frase longa, rotação e Undo inspecionados.
- A revisão da sequência revelou um halo deslocado durante a medição do foco após fusão. A última geometria válida agora é retida nesse intervalo. Build e percurso Metal com A/B, rotação e Undo aprovados novamente (`build/atmosphere-focus-continuity.xcresult`); nova sequência inspecionada.
- Uma execução do teste aleatório de física excedeu o limite de centralização (4,45 pt contra 4 pt). Sem alterações nesse código; os 4 testes de física passaram isoladamente em `build/physics-recheck.xcresult`. Detalhes e nomes das capturas no README.

## Preparação para integração

- Branch atualizada com `main` em `4a286ee`. Conflitos restritos a README e HANDOFF, conciliando o experimento Metal com onboarding, capturas versionadas e o estado atual do motor local.
- Código do app, testes, scripts e configuração do projeto idênticos aos do experimento validado em `08eb506`; testes anteriores continuam aplicáveis. Build repetido após a atualização, aprovado (`build/merge-prep-build.log`).
- Integrada a `main` em `bed3303`; em seguida `exp/long-press-split` (`fd14e01`) entrou por cima, com conflitos de texto em README e SPEC e o `.xcodeproj` regenerado por XcodeGen.
- Destino: `main` em `~/dev/TesteMetaWord`. Worktrees encerradas. Capturas-chave do Metal versionadas em `docs/media/metal/`; PNGs originais, sequências, logs e `.xcresult` arquivados em `~/dev/TesteMetaWord-artifacts/metal-atmosphere` (fora do Git).

## Pendências

- Avaliação manual da sensação do gesto e da física, do idle em uso de C.A., da membrana, do long press, do VoiceOver, do desempenho; iPad físico.
- Fora desta iteração:
  - tint do vidro;
  - hierarquia visual da frase;
  - membrana em rubber band;
  - glifo do Undo;
  - ordem espacial do VoiceOver.
- Motor de IA local: seam pronto no app (`CompositionEngine`, `RuleEngine`, `Composition.refresh()`). Rodada 2 do LoRA treinada e avaliada (`ml/README.md`). Próximo: fundir/quantizar o adaptador r2 e implementar `LocalModelEngine` com MLX Swift só para fusões (validar em iPad físico).
- Prospecção de longo prazo (vocabulário aberto, dados, treino, avaliação e outros idiomas): [future-HANDOFF.md](future-HANDOFF.md).
