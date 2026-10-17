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

Também é possível tocar querer → ir → um dos dois. Tocar no fundo cancela. `<` desfaz, dividindo o resultado; pressionar o resultado da última fusão por 0,6 s também desfaz: durante a pressão a bolha treme cada vez mais e um som tremular cresce, até estourar com um estalo no instante da divisão (o iPad não tem háptico para o dedo; o som faz esse papel). O botão de ajustes abre a calibração da distância de aproximação.

Estado e parâmetros vivem apenas na sessão. Sem SwiftData, voz ou serviços remotos.

## Código

- `TesteMetaWord/Composition.swift`: estado, gestos, fusão, Undo, foco e zonas lidos do último léxico do motor.
- `TesteMetaWord/CompositionEngine.swift`: contrato do motor (`lexicon(for:focus:)`) e `RuleEngine`, o motor padrão e fallback.
- `TesteMetaWord/Vocabulary.swift`: combinações locais e relevância (`zone`) usadas pelo `RuleEngine`.
- `ml/`: preparação do motor por modelo local (dataset, LoRA, avaliação); ver `ml/README.md`.
- `TesteMetaWord/Physics.swift`: física pura (repulsão, slots por zona, nascimento, órbita) com as constantes nomeadas.
- `TesteMetaWord/ContentView.swift`: canvas, `TimelineView` como relógio da física, atmosferas, gestos e animações.
- `TesteMetaWord/ChipView.swift`: cápsula de vidro, estado armado e pulso.
- `TesteMetaWord/SplitTension.swift`: tensão do long press (curva do tremor, síntese do som tremular e do estouro, reprodução).
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
python3 scripts/capture-atmosphere.py <UDID> --label normal-complete
```

O script executa a suíte completa com `xcodebuild test`; use `--only-atmosphere` para repetir apenas o percurso visual. Usa somente a biblioteca padrão do Python 3. Cada `--label` deve ser novo, pois preserva o `.xcresult` anterior. Logs, resultados, capturas PNG e anexos exportados ficam em `build/`. O XCTest segura o arrasto por 8 s; `simctl` captura enquanto ele permanece pressionado. Sequências `fusion` e `split` registram a reorganização e o Undo.

## Resultado da validação: 16/10/2026

- **Build:** `./scripts/build.sh` aprovado para iPadOS sem assinatura, Xcode 26.4.1. Aviso de extração de metadados App Intents ignorada, pois o app não usa o framework.
- **Testes:** suíte completa aprovada no iPad Pro 13-inch (M5), iOS 26.4: 21 testes Swift Testing e 3 XCTest de interface. Cobrem o motor local, vocabulário, estados de gesto, Undo, foco/zonas, física/órbitas, soltura superficial e três fusões reais até “Eu quero comer agora”.
- **Evidência visual no simulador** (`docs/media/`, reduzidas a partir das capturas do script):
  - `atmosphere-initial.jpg`: somente a Zona 1 ocupada emite luz; fundo noturno contínuo, sem as três cápsulas sólidas.
  - `atmosphere-armed.jpg`: par eu/querer sobreposto durante o arrasto mantido por XCTest; “Solte para combinar” confirma o estado armado. Luz localizada e reforço da zona interna.
  - `atmosphere-first-fusion.jpg`: “Eu quero” no foco após a primeira fusão.
  - `atmosphere-long-phrase.jpg`: frase longa com largura proporcional, centro neutro e apenas a Zona 3 iluminada.
  - `atmosphere-undo.jpg`: volta a “Eu quero comer”, com agora/depois na zona interna.
  - As sequências de reorganização após fusão e divisão por Undo (`build/atmosphere-{fusion,split}-<label>-*.png`, geradas pelo script) não mostraram ruptura do fundo, degraus ou bandas; a vinheta foi estendida atrás das barras para eliminar uma emenda retangular observada na primeira captura.
- O teste de soltura superficial passou após estabilizar a automação: medidas dos chips lidas uma vez e destino fixado no canvas. A versão anterior relia a órbita durante a bisseção e ancorava o destino no próprio chip em movimento, podendo terminar em sobreposição profunda.
- **Pendente no iPad físico:** sensação do gesto e do timing, uso de alvos em movimento para C.A., membrana, long press, VoiceOver, teclado/trackpad e desempenho do vidro. Nenhum formatter/linter foi executado.
