# TesteMetaWord

Laboratório SwiftUI para iPadOS 26+: palavras em Liquid Glass numa grid circular orgânica, com centro óptico, zonas de relevância, fusão ao arrastar e soltar (mitose reversa), sugestões que brotam do resultado (mitose), alternativa por toque e Undo. Veja [SPEC.md](SPEC.md).

Abra `TesteMetaWord.xcodeproj` no Xcode 26+. Para dispositivo físico, configure sua equipe em Signing & Capabilities.

## Versionamento

`main` guarda a base de referência; experimentos usam branches `exp/<nome>` e
worktrees sob demanda. A integração é por merge local, sem PR obrigatório.
Veja os comandos e a estrutura em [Git no LAB](docs/GIT.md).

## Uso

Ao abrir, as palavras brotam do centro; **querer** (a palavra com mais combinações) é o centro óptico, cercado pela zona interna. Arraste **ir** sobre **querer** até armar (realce branco e pulso) e solte: as duas convergem, **Quero ir** nasce no ponto de encontro, **agora** e **depois** brotam dele, e **Quero ir** migra para o centro. Palavras que combinam com o foco ficam na zona interna; as que só combinam entre si, na média; as sem combinação, na externa. Durante o gesto a composição fica parada; ela se reorganiza depois.

Também é possível tocar querer → ir → um dos dois. Tocar no fundo cancela. `<` desfaz, dividindo o resultado; pressionar o resultado da última fusão por 0,6 s também desfaz. O botão de ajustes abre a calibração da distância de aproximação.

Estado e parâmetros vivem apenas na sessão. Sem SwiftData, voz ou serviços remotos.

## Código

- `TesteMetaWord/Composition.swift`: estado, gestos, fusão, Undo, foco e zonas lidos do último léxico do motor.
- `TesteMetaWord/CompositionEngine.swift`: contrato do motor (`lexicon(for:focus:)`) e `RuleEngine`, o motor padrão e fallback.
- `TesteMetaWord/Vocabulary.swift`: combinações locais e relevância (`zone`) usadas pelo `RuleEngine`.
- `ml/`: preparação do motor por modelo local (dataset, LoRA, avaliação); ver `ml/README.md`.
- `TesteMetaWord/Physics.swift`: física pura (repulsão, slots por zona, nascimento, órbita) com as constantes nomeadas.
- `TesteMetaWord/ContentView.swift`: canvas, `TimelineView` como relógio da física, atmosferas, gestos e animações.
- `TesteMetaWord/ChipView.swift`: cápsula de vidro, estado armado e pulso.

## Build e testes

```sh
xcodegen generate
./scripts/build.sh
xcodebuild test -project TesteMetaWord.xcodeproj -scheme TesteMetaWord -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -derivedDataPath build/DerivedData -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
```

Se o ambiente impedir o sandbox de macros, use `./scripts/build.sh 'OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox'`.

Build para dispositivo sem assinatura: `build/DerivedData/Build/Products/Debug-iphoneos/TesteMetaWord.app`.

## Resultado da validação — 16/10/2026

- Build sem assinatura para iPadOS aprovado (Xcode 26.4.1). O build emite apenas o aviso de metadados App Intents ignorados.
- 19 testes Swift Testing e 2 testes de interface (XCTest) passaram no iPad Pro 13-inch (M5), iOS 26.4. Lógica: vocabulário, armar/desarmar, confirmação, cancelamento, Undo, foco e zonas, fases das órbitas, física (foco no centro, zonas no gap-alvo, sem pontes em repouso, distribuição uniforme, nascimento) e órbita. Interface: arrastar e soltar gera “Quero ir” + sugestões sem toque extra e desfaz; soltura a 6 pt da superfície não funde e a física reabre o espaço.
- Simulador, por capturas sequenciais durante o teste de interface (`simctl recordVideo` falhou neste ambiente com `SimRenderServer` erro 2):
  - `build/zones-initial.png`: querer no centro óptico, cinco palavras na zona interna, três halos de atmosfera.
  - `build/zones-fusion-frames.png`: composição parada durante o arrasto; convergência com vidro cheio; ponte de vidro esticando enquanto as sugestões brotam; resultado migrando para o centro; Undo dividindo o resultado.
  - `build/zones-after-fusion.png`: “Quero ir” no centro, eu/agora/depois na zona interna, brincar/comer/beber na externa.
- Corrigido durante a validação: `.disabled` esmaecia todas as palavras na fusão; uma troca de `zIndex` no início da convergência fazia o vidro rematerializar (cápsula escura).
- Simulação offline das constantes: foco centralizado, zonas a até 8 pt do gap-alvo, gap mínimo ≥ 35 pt, assentamento em cerca de 1,3 s (velocidade < 5 pt/s).
- Pendente de avaliação humana: sensação da física e do timing no dedo, flutuação idle em uso real (alvos em movimento para C.A.), membrana, long press, VoiceOver, teclado/trackpad, movimento reduzido, desempenho do vidro reavaliado a cada frame e iPad físico. Nenhum formatter/linter foi executado.
