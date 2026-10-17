# TesteMetaWord

Laboratório SwiftUI para iPadOS 26+: palavras em Liquid Glass numa grid circular orgânica, com centro óptico, zonas de relevância, fusão ao arrastar e soltar (mitose reversa), sugestões que brotam do resultado (mitose), alternativa por toque e Undo. Veja [SPEC.md](SPEC.md).

**Equipe que assume o projeto:** comece por [docs/ONBOARDING.md](docs/ONBOARDING.md) (origem do protótipo, intenção de design, estado e briefing para agentes de IA). Prospecção de longo prazo em [future-HANDOFF.md](future-HANDOFF.md).

Abra `TesteMetaWord.xcodeproj` no Xcode 26+. Para dispositivo físico, configure sua equipe em Signing & Capabilities.

## Versionamento

`main` guarda a base de referência; experimentos usam branches `exp/<nome>` e
worktrees sob demanda. A integração é por merge local, sem PR obrigatório.
Veja os comandos e a estrutura em [Git no LAB](docs/GIT.md).

## Uso

Ao abrir, as palavras brotam do centro; **querer** (a palavra com mais combinações) é o centro óptico, cercado pela zona interna. Arraste **ir** sobre **querer** até armar (realce branco e pulso) e solte: as duas convergem, **Quero ir** nasce no ponto de encontro, **agora** e **depois** brotam dele, e **Quero ir** migra para o centro. Palavras que combinam com o foco ficam na zona interna; as que só combinam entre si, na média; as sem combinação, na externa. Durante o gesto a composição fica parada; ela se reorganiza depois. Sobre a BubbleKey, o dedo escolhe a fresta: arraste **eu** até a ponta esquerda de **Quero ir** e a frase se abre ali (“Eu quero ir”); na ponta direita, “Quero ir eu”. Num par por toque, as setas ← → movem a fresta.

Com dois dedos, repouse um sobre **querer** e outro sobre **ir** e aproxime-os numa pinça até armar; tirar um dos dedos funde. Também é possível tocar querer → ir → um dos dois. Tocar no fundo cancela. `<` desfaz, dividindo o resultado; pressionar o resultado da última fusão por 0,6 s também desfaz: durante a pressão a bolha treme cada vez mais e um som tremular cresce, até a divisão, marcada por uma nota curta (o iPad não tem háptico para o dedo; o som faz esse papel). Os sons são de fundo: fusão, divisão, erro da pinça incompatível e um tom contínuo que acompanha a profundidade da sobreposição, em volume baixo, e o interruptor "Sons" os silencia. O botão de ajustes abre a calibração da distância de aproximação, o interruptor de sons e a escolha de atmosfera Metal/Gradientes. Metal é o padrão nesta branch; Gradientes mantém a referência para comparação. O painel confirma qual desenho está ativo. A troca preserva a composição e o Undo, e não é salva entre sessões.

Estado e parâmetros vivem apenas na sessão. Sem SwiftData, voz ou serviços remotos.

## Código

- `TesteMetaWord/Composition.swift`: estado, gestos, fusão, Undo, foco e zonas lidos do último léxico do motor.
- `TesteMetaWord/CompositionEngine.swift`: contrato do motor (`lexicon(for:focus:)`) e `RuleEngine`, o motor padrão e fallback.
- `TesteMetaWord/Vocabulary.swift`: palavras iniciais, combinações e relevância (`zone`) usadas pelo `RuleEngine`.
- `TesteMetaWord/Grammar.swift`: gramática procedural de fusão, lida de `ml/vocabulary.json` (recurso do app e fonte do dataset; ver `SPEC.md`).
- `ml/`: preparação do motor por modelo local (dataset, LoRA, avaliação); ver `ml/README.md`.
- `TesteMetaWord/Physics.swift`: física pura (repulsão, slots por zona, nascimento, órbita) com as constantes nomeadas.
- `TesteMetaWord/ContentView.swift`: canvas, `TimelineView` como relógio da física, atmosferas, gestos e animações.
- `TesteMetaWord/AtmosphereView.swift`: parâmetros do shader da atmosfera e sua interpolação.
- `TesteMetaWord/Atmosphere.metal`: faixas suaves, união luminosa das cápsulas e deformação localizada.
- `TesteMetaWord/ChipView.swift`: cápsula de vidro, estado armado e pulso; a BubbleKey palavra por palavra, com a fresta aberta.
- `TesteMetaWord/PhraseLayout.swift`: molduras das palavras pelo layout de texto, fresta sob o dedo (com histerese) e alvos de cada palavra.
- `TesteMetaWord/TouchTracker.swift`: observador UIKit dos dedos na tela (posição e quantidade), sem consumir toques; base da pinça.
- `TesteMetaWord/SplitTension.swift`: tensão do long press (curva do tremor, síntese do som tremular, reprodução).
- `TesteMetaWord/Sfx.swift`: sons de fundo sintetizados (fusão, divisão, erro) e seu player.
- `TesteMetaWord/Shake.swift`: reconhecimento da sacudida no arrasto.

## Build e testes

```sh
xcodegen generate          # só ao criar ou remover arquivos
./scripts/build.sh
./scripts/test.sh          # testes de lógica, o ciclo do dia a dia (~15 s com build)
./scripts/test.sh ui       # o percurso único de interface (~25 s)
./scripts/test.sh all      # os dois, antes de integrar em main
```

A saída é silenciosa (`-quiet`): só falhas e o resumo; código de saída 0 é aprovado. `DESTINATION='platform=iOS Simulator,id=<UDID>'` escolhe outro simulador.

Se o ambiente impedir o sandbox de macros, use `./scripts/build.sh 'OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox'`.

Build para dispositivo sem assinatura: `build/DerivedData/Build/Products/Debug-iphoneos/TesteMetaWord.app`.

Validação mínima: build, testes de lógica e um percurso de interface básico. Não há testes nem scripts de comparação visual; crashes e erros críticos são relatados pela pessoa usuária (ver `AGENTS.md`, “Validação”).

> **Histórico:** o renderizador por gradientes, o interruptor de sons e o script `scripts/capture-atmosphere.py` foram removidos em `exp/gramatica-procedural`. As seções abaixo registram experimentos anteriores e citam esses recursos como estavam.

## Referência preservada

O fundo por gradientes foi salvo em `6543743`, com build aprovado e 21 testes de lógica + 3 de interface. Esse commit é a base deste experimento e foi integrado a `main` por `4a286ee`. As capturas da referência estão versionadas em [docs/media](docs/media): `atmosphere-{initial,armed,first-fusion,long-phrase,undo}.jpg`. A worktree anterior foi encerrada; as novas capturas de comparação com Metal ficam no `build/` deste experimento.

## Experimento Metal

Branch `exp/metal-atmosphere`, worktree `TesteMetaWord-wt-metal-atmosphere`. Shader como preenchimento SwiftUI, atrás do Liquid Glass nativo. Sem renderizador MetalKit, alteração do motor de composição ou da física. O projeto foi regenerado com XcodeGen; `project.yml` já cobre os novos arquivos pelo diretório de fontes.

A comparação é visual e funcional no simulador. Desempenho, consumo e sensação no iPad físico ficam para uma avaliação posterior; não há alegação de ganho de FPS ou energia.

## Validação do Metal: 16/10/2026

Os caminhos `build/…` desta seção eram da worktree encerrada; os arquivos estão em `~/dev/TesteMetaWord-artifacts/metal-atmosphere`, fora do Git.

- **Build:** `./scripts/build.sh` aprovado para iPadOS sem assinatura, com a biblioteca `default.metallib` no app. Projeto regenerado com XcodeGen. Apenas o aviso de metadados App Intents ignorados.
- **Suíte completa:** 23 testes Swift Testing e 5 XCTest de interface aprovados no simulador dedicado “TesteMetaWord Atmosphere”, iPad Pro 13-inch (M5), iOS 26.4. Resultado: `build/atmosphere-compare-final.xcresult`.
- **Percursos visuais:** três fusões reais em cada renderizador, troca de modo com preservação das palavras/corpos/Undo, rotação e resistência superficial. Na captura refinada, o primeiro arrasto segura 60% de sobreposição por 8 s, mantendo as duas palavras visíveis antes de soltar. Os 5 testes de interface passaram novamente em `build/atmosphere-verified.xcresult`.
- **Rotação:** repetição do percurso Metal aprovada em `build/atmosphere-rotation.xcresult`. A captura foi alterada para `XCUIScreen.main.screenshot()` porque a captura do app conservava um recorte de retrato durante a rotação. A tela inteira e a captura externa por `simctl` confirmam o conteúdo completo em paisagem; o PNG bruto do `simctl` segue a orientação física do display.
- **Continuidade final:** a sequência revelou um halo deslocado enquanto o foco recém-fundido aguardava sua medição. A atmosfera passou a reter a geometria anterior nesse intervalo. Build aprovado novamente e percurso Metal com três fusões, A/B, rotação e Undo aprovado em `build/atmosphere-focus-continuity.xcresult`; a nova sequência de fusão mantém a luz junto aos chips.
- **Instabilidade observada:** na execução `verified`, o teste existente `focusCentersAndEachZoneSettlesOnItsOwnRingWithoutGlassBridges` falhou com distância de 4,45 pt para um limite de 4 pt. O teste usa UUIDs e impulsos aleatórios; a física e esse teste não foram alterados. Os quatro testes de física passaram na repetição isolada (`build/physics-recheck.xcresult`). Essa instabilidade continua registrada, sem relaxar o limite do teste.

Capturas inspecionadas (versionadas, reduzidas, em [docs/media/metal](docs/media/metal); originais PNG, sequências, logs e `.xcresult` arquivados fora do repositório em `~/dev/TesteMetaWord-artifacts/metal-atmosphere`, na máquina do autor):

| Captura | Evidência |
| --- | --- |
| `atmosphere-initial-metal-rotation.jpg` | Repouso discreto e somente Zona 1 iluminada |
| `atmosphere-armed-metal-verified-2.jpg` | Luz acompanha as superfícies eu/querer em sobreposição parcial armada |
| `atmosphere-armed-gradients-verified-2.jpg` | Referência elíptica no mesmo estado de intenção |
| `atmosphere-comparison-{metal,gradients}-rotation.jpg` | Mesma frase e composição nos dois modos; centro neutro com Zona 1 vazia |
| `atmosphere-landscape-metal-rotation.jpg` | Frase longa e palavras periféricas completas em paisagem |
| `atmosphere-undo-metal-rotation.jpg` | Retorno a “Eu quero comer” e recomposição das zonas |
| `atmosphere-resistance-metal-verified.jpg` | Luz atenuada e separação visual durante pressão superficial |
| `atmosphere-{fusion,split}-metal-focus-continuity-*.png` (só no arquivo externo) | Continuidade após fusão e Undo, com retenção da última geometria válida |

A inspeção mostrou luz distribuída pelo contorno do par no Metal, queda suave sem degraus perceptíveis e canvas contínuo nas duas orientações. A diferença é localizada no gesto; o repouso mantém a referência noturna. Desempenho, consumo e sensação no iPad físico não foram medidos. Nenhum formatter/linter foi executado.

## Experimento pinça: 16/10/2026

Branch `exp/pinca`, worktree `TesteMetaWord-wt-pinca`. Um dedo repousado sobre cada uma de duas bolhas seleciona o par; aproximá-las arma pela mesma regra de 45% e soltar o primeiro dedo armado confirma. Regras completas em `SPEC.md` (“Pinça”). `TouchTracker.swift` observa os dedos via UIKit sem consumir toques, porque o SwiftUI não informa dedos parados nem quantos estão na tela.

- **Build:** aprovado; projeto regenerado com XcodeGen.
- **Testes:** 33 Swift Testing (6 novos em `PinchTests`: armar e confirmar, soltar abaixo do limiar, desarmar ao afastar, par incompatível só com resistência, pinça substitui seleção/arrasto, bolha sob o dedo) e 8 XCTest de interface, todos aprovados. Os 7 testes de interface anteriores provam que o observador não quebrou arrasto, soltura superficial, atmosfera, troca de renderizador e long press.
- **Dois dedos reais:** `testTwoFingersOnOneBubbleDoNotPinchOrSplit` faz uma pinça de ~1,5 s sobre o resultado da fusão: nenhuma pinça começa (dois dedos na mesma bolha) e o long press não divide.
- **Limite do XCTest:** `pinch(withScale:)` pousa os dois dedos na diagonal da moldura de um único elemento (medido no passo 0: cerca de 94%/4% e 10%/80% da largura/altura). Como as posições das bolhas variam a cada abertura, não há teste automatizado confiável da pinça entre duas bolhas. Exceção registrada à regra de validar o gesto inteiro em teste de interface.
- **Simulador (validação manual do autor, 16/10/2026):** pinça entre duas bolhas funcional (Option mostra dois dedos; Shift+Option move o ponto médio). Divisão por long press com tremor e som também conferida (antes dos sons de fundo atuais; a escuta dos sons discretos novos ainda não foi registrada).
- **Pendente no iPad físico:** dedos reais, terceiro dedo, dedo que sobra após a fusão, folga entre dedos em chips largos e pequenos.
