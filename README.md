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
- `scripts/capture-atmosphere.py`: testes e capturas da atmosfera, incluindo o arrasto mantido em estado armado.

## Build e testes

```sh
xcodegen generate
./scripts/build.sh
xcodebuild test -project TesteMetaWord.xcodeproj -scheme TesteMetaWord -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -derivedDataPath build/DerivedData -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
```

Se o ambiente impedir o sandbox de macros, use `./scripts/build.sh 'OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox'`.

Build para dispositivo sem assinatura: `build/DerivedData/Build/Products/Debug-iphoneos/TesteMetaWord.app`.

Para capturar a atmosfera sem disputar o simulador de outro experimento, use um iPad dedicado já iniciado e seu UDID em `ATMOSPHERE_DEVICE`:

```sh
ATMOSPHERE_DEVICE=BA1C5382-C4B3-4FFA-A009-6A5228047E68
python3 scripts/capture-atmosphere.py "$ATMOSPHERE_DEVICE" --label normal-complete
```

O script executa a suíte completa com `xcodebuild test`; use `--only-atmosphere` para repetir apenas o percurso visual. Usa somente a biblioteca padrão do Python 3. Cada `--label` deve ser novo, pois preserva o `.xcresult` anterior. Logs, resultados, capturas PNG e anexos exportados ficam em `build/`. O XCTest segura o arrasto por 8 s; `simctl` captura enquanto ele permanece pressionado. Sequências `fusion` e `split` registram a reorganização e o Undo.

## Resultado da validação: 16/10/2026

- **Build:** `./scripts/build.sh` aprovado para iPadOS sem assinatura, Xcode 26.4.1. Aviso de extração de metadados App Intents ignorada, pois o app não usa o framework.
- **Testes:** suíte completa aprovada no simulador dedicado “TesteMetaWord Atmosphere”, iPad Pro 13-inch (M5), iOS 26.4: 21 testes Swift Testing e 3 XCTest de interface. Cobrem o motor local, vocabulário, estados de gesto, Undo, foco/zonas, física/órbitas, soltura superficial e três fusões reais até “Eu quero comer agora”. Resultado: `build/atmosphere-normal-complete.xcresult`.
- **Evidência visual no simulador:**
  - `build/atmosphere-initial-normal-complete.png`: somente a Zona 1 ocupada emite luz; fundo noturno contínuo, sem as três cápsulas sólidas.
  - `build/atmosphere-armed-normal-complete-2.png`: par eu/querer sobreposto durante o arrasto mantido por XCTest; “Solte para combinar” confirma o estado armado. Luz localizada e reforço da zona interna.
  - `build/atmosphere-first-fusion-normal-complete.png`: “Eu quero” no foco após a primeira fusão.
  - `build/atmosphere-long-phrase-normal-complete.png`: frase longa com largura proporcional, centro neutro e apenas a Zona 3 iluminada.
  - `build/atmosphere-undo-normal-complete.png`: volta a “Eu quero comer”, com agora/depois na zona interna.
  - `build/atmosphere-fusion-normal-complete-*.png` e `build/atmosphere-split-normal-complete-*.png`: sequência de reorganização após fusão e divisão por Undo, sem ruptura do fundo. Inspeção sem degraus ou bandas perceptíveis; a vinheta foi estendida atrás das barras para eliminar uma emenda retangular observada na primeira captura.
- O teste de soltura superficial passou após estabilizar a automação: medidas dos chips lidas uma vez e destino fixado no canvas. A versão anterior relia a órbita durante a bisseção e ancorava o destino no próprio chip em movimento, podendo terminar em sobreposição profunda.
- **Pendente no iPad físico:** sensação do gesto e do timing, uso de alvos em movimento para C.A., membrana, long press, VoiceOver, teclado/trackpad e desempenho do vidro. Nenhum formatter/linter foi executado.
