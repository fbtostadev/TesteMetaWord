# TesteMetaWord

Laboratório SwiftUI para iPadOS 26+: palavras em Liquid Glass numa grid circular orgânica, com centro óptico, zonas de relevância, fusão ao arrastar e soltar (mitose reversa), sugestões que brotam do resultado (mitose), alternativa por toque e Undo. Veja [SPEC.md](SPEC.md).

**Equipe que assume o projeto:** comece por [docs/ONBOARDING.md](docs/ONBOARDING.md) (origem do protótipo, intenção de design, estado e briefing para agentes de IA). Prospecção de longo prazo em [future-HANDOFF.md](future-HANDOFF.md).

Abra `TesteMetaWord.xcodeproj` no Xcode 26+. Para dispositivo físico, configure sua equipe em Signing & Capabilities.

## Versionamento

`main` guarda a base de referência; experimentos usam branches `exp/<nome>` e
worktrees sob demanda. A integração é por merge local, sem PR obrigatório.
Veja os comandos e a estrutura em [Git no LAB](docs/GIT.md).

## Uso

Ao abrir, as palavras brotam do centro; **querer** (a palavra com mais combinações) é o centro óptico, cercado pela zona interna. Arraste **ir** sobre **querer** até armar (realce branco e pulso) e solte: as duas convergem, **Quero ir** nasce no ponto de encontro, **agora** e **depois** brotam dele, e **Quero ir** migra para o centro. Palavras que combinam com o foco ficam na zona interna; as que só combinam entre si, na média; as sem combinação, na externa. Durante o gesto a composição fica parada; ela se reorganiza depois.

Também é possível tocar querer → ir → um dos dois. Tocar no fundo cancela. `<` desfaz, dividindo o resultado; pressionar o resultado da última fusão por 0,6 s também desfaz. O botão de ajustes abre a calibração da distância de aproximação e a escolha de atmosfera Metal/Gradientes. Metal é o padrão nesta branch; Gradientes mantém a referência para comparação. O painel confirma qual desenho está ativo. A troca preserva a composição e o Undo, e não é salva entre sessões.

Estado e parâmetros vivem apenas na sessão. Sem SwiftData, voz ou serviços remotos.

## Código

- `TesteMetaWord/Composition.swift`: estado, gestos, fusão, Undo, foco e zonas lidos do último léxico do motor.
- `TesteMetaWord/CompositionEngine.swift`: contrato do motor (`lexicon(for:focus:)`) e `RuleEngine`, o motor padrão e fallback.
- `TesteMetaWord/Vocabulary.swift`: combinações locais e relevância (`zone`) usadas pelo `RuleEngine`.
- `ml/`: preparação do motor por modelo local (dataset, LoRA, avaliação); ver `ml/README.md`.
- `TesteMetaWord/Physics.swift`: física pura (repulsão, slots por zona, nascimento, órbita) com as constantes nomeadas.
- `TesteMetaWord/ContentView.swift`: canvas, `TimelineView` como relógio da física, atmosferas, gestos e animações.
- `TesteMetaWord/AtmosphereView.swift`: parâmetros compartilhados, interpolação e referência por gradientes.
- `TesteMetaWord/Atmosphere.metal`: faixas suaves, união luminosa das cápsulas e deformação localizada.
- `TesteMetaWord/ChipView.swift`: cápsula de vidro, estado armado e pulso.
- `scripts/capture-atmosphere.py`: testes e capturas da atmosfera, incluindo o arrasto mantido em estado armado.

## Build e testes

```sh
xcodegen generate
./scripts/build.sh
xcodebuild test -project TesteMetaWord.xcodeproj -scheme TesteMetaWord -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -derivedDataPath build/DerivedData -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
```

Se o ambiente impedir o sandbox de macros, use `./scripts/build.sh 'OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox'`.

Build para dispositivo sem assinatura: `build/DerivedData/Build/Products/Debug-iphoneos/TesteMetaWord.app`.

Para capturar a atmosfera sem disputar o simulador de outro experimento, use um iPad dedicado já iniciado e passe seu UDID (`xcrun simctl list devices booted`):

```sh
python3 scripts/capture-atmosphere.py <UDID> --label comparacao-01
```

O script executa a suíte completa com `xcodebuild test`; use `--only-atmosphere` para repetir os dois percursos visuais e a soltura superficial; `--only-metal` executa somente o percurso Metal com A/B e rotação. Usa somente a biblioteca padrão do Python 3. Cada `--label` deve ser novo, pois preserva o `.xcresult` anterior. Logs, resultados, capturas PNG e anexos exportados ficam em `build/`. O XCTest segura o arrasto por 8 s; `simctl` captura enquanto ele permanece pressionado. Os nomes incluem `metal` ou `gradients`. Sequências `fusion` e `split` registram a reorganização e o Undo; `resistance` registra a pressão superficial. O teste abre a calibração e exige “Metal ativo”, para não aceitar o fallback como evidência do shader. O argumento `--atmosphere-renderer=gradients` permite iniciar a referência na automação.

## Referência preservada

O fundo por gradientes foi salvo em `6543743`, com build aprovado e 21 testes de lógica + 3 de interface. Esse commit é a base deste experimento e foi integrado a `main` por `4a286ee`. As capturas da referência estão versionadas em [docs/media](docs/media): `atmosphere-{initial,armed,first-fusion,long-phrase,undo}.jpg`. A worktree anterior foi encerrada; as novas capturas de comparação com Metal ficam no `build/` deste experimento.

## Experimento Metal

Branch `exp/metal-atmosphere`, worktree `TesteMetaWord-wt-metal-atmosphere`. Shader como preenchimento SwiftUI, atrás do Liquid Glass nativo. Sem renderizador MetalKit, alteração do motor de composição ou da física. O projeto foi regenerado com XcodeGen; `project.yml` já cobre os novos arquivos pelo diretório de fontes.

A comparação é visual e funcional no simulador. Desempenho, consumo e sensação no iPad físico ficam para uma avaliação posterior; não há alegação de ganho de FPS ou energia.

## Validação do Metal: 16/10/2026

- **Build:** `./scripts/build.sh` aprovado para iPadOS sem assinatura, com a biblioteca `default.metallib` no app. Projeto regenerado com XcodeGen. Apenas o aviso de metadados App Intents ignorados.
- **Suíte completa:** 23 testes Swift Testing e 5 XCTest de interface aprovados no simulador dedicado “TesteMetaWord Atmosphere”, iPad Pro 13-inch (M5), iOS 26.4. Resultado: `build/atmosphere-compare-final.xcresult`.
- **Percursos visuais:** três fusões reais em cada renderizador, troca de modo com preservação das palavras/corpos/Undo, rotação e resistência superficial. Na captura refinada, o primeiro arrasto segura 60% de sobreposição por 8 s, mantendo as duas palavras visíveis antes de soltar. Os 5 testes de interface passaram novamente em `build/atmosphere-verified.xcresult`.
- **Rotação:** repetição do percurso Metal aprovada em `build/atmosphere-rotation.xcresult`. A captura foi alterada para `XCUIScreen.main.screenshot()` porque a captura do app conservava um recorte de retrato durante a rotação. A tela inteira e a captura externa por `simctl` confirmam o conteúdo completo em paisagem; o PNG bruto do `simctl` segue a orientação física do display.
- **Continuidade final:** a sequência revelou um halo deslocado enquanto o foco recém-fundido aguardava sua medição. A atmosfera passou a reter a geometria anterior nesse intervalo. Build aprovado novamente e percurso Metal com três fusões, A/B, rotação e Undo aprovado em `build/atmosphere-focus-continuity.xcresult`; a nova sequência de fusão mantém a luz junto aos chips.
- **Instabilidade observada:** na execução `verified`, o teste existente `focusCentersAndEachZoneSettlesOnItsOwnRingWithoutGlassBridges` falhou com distância de 4,45 pt para um limite de 4 pt. O teste usa UUIDs e impulsos aleatórios; a física e esse teste não foram alterados. Os quatro testes de física passaram na repetição isolada (`build/physics-recheck.xcresult`). Essa instabilidade continua registrada, sem relaxar o limite do teste.

Capturas inspecionadas em `build/`:

| Captura | Evidência |
| --- | --- |
| `atmosphere-initial-metal-rotation.png` | Repouso discreto e somente Zona 1 iluminada |
| `atmosphere-armed-metal-verified-2.png` | Luz acompanha as superfícies eu/querer em sobreposição parcial armada |
| `atmosphere-armed-gradients-verified-2.png` | Referência elíptica no mesmo estado de intenção |
| `atmosphere-comparison-{metal,gradients}-rotation.png` | Mesma frase e composição nos dois modos; centro neutro com Zona 1 vazia |
| `atmosphere-landscape-metal-rotation.png` | Frase longa e palavras periféricas completas em paisagem |
| `atmosphere-undo-metal-rotation.png` | Retorno a “Eu quero comer” e recomposição das zonas |
| `atmosphere-resistance-metal-verified.png` | Luz atenuada e separação visual durante pressão superficial |
| `atmosphere-{fusion,split}-metal-focus-continuity-*.png` | Continuidade após fusão e Undo, com retenção da última geometria válida |

A inspeção mostrou luz distribuída pelo contorno do par no Metal, queda suave sem degraus perceptíveis e canvas contínuo nas duas orientações. A diferença é localizada no gesto; o repouso mantém a referência noturna. Desempenho, consumo e sensação no iPad físico não foram medidos. Nenhum formatter/linter foi executado.
