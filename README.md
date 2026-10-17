# TesteMetaWord

Laboratório SwiftUI para iPadOS 26+ sobre comunicação alternativa (C.A.). Cada palavra é um chip de Liquid Glass numa grid circular orgânica, com um centro óptico e zonas de relevância ao redor. Arrastar uma palavra sobre outra funde as duas, como numa mitose reversa, e do resultado brotam novas sugestões. Também há alternativa por toque, pinça com dois dedos e Undo. O comportamento completo está em [SPEC.md](SPEC.md).

Se você está assumindo o projeto, comece por [docs/ONBOARDING.md](docs/ONBOARDING.md): origem do protótipo, intenção de design, estado atual e um briefing para agentes de IA. O roteiro de longo prazo está em [future-HANDOFF.md](future-HANDOFF.md).

## Rodar num iPad

Você precisa de um Mac com Xcode 26+ e de um iPad com iPadOS 26 ou superior e Modo de Desenvolvedor ligado (Ajustes › Privacidade e Segurança). O app é só para iPad. Uma conta Apple gratuita basta, mas nesse caso o app instalado expira em 7 dias.

1. Troque o bundle identifier. O atual, `com.fabriciotosta.TesteMetaWord`, pertence à conta do autor, e a assinatura automática falha com "bundle identifier not available". Em `project.yml`, troque `com.fabriciotosta` por um prefixo seu nos três `PRODUCT_BUNDLE_IDENTIFIER` e rode `xcodegen generate` (instale com `brew install xcodegen`). Mudar só no Xcode não adianta, porque o próximo `xcodegen generate` desfaz.
2. Abra `TesteMetaWord.xcodeproj`, selecione o target `TesteMetaWord`, vá em Signing & Capabilities e escolha sua equipe.
3. Conecte o iPad, escolha-o como destino e rode com ⌘R. Na primeira vez, confie no desenvolvedor em Ajustes › Geral › VPN e Gerenciamento de Dispositivo.

Até agora o app só foi visto no simulador. Ninguém o rodou num iPad físico (ver "Estado na entrega" no [onboarding](docs/ONBOARDING.md)).

## Como usar

Ao abrir, as palavras brotam do centro. **Querer**, a palavra com mais combinações, é o centro óptico. As outras ficam em três zonas ao redor, de acordo com a força da fusão com o foco: na interna a fusão forma uma frase da gramática, na média sai uma frase telegráfica ou reparada, e na externa as palavras se coordenam com "e". Toda palavra se funde com qualquer outra.

**Arrastar.** Arraste **ir** sobre **querer** até o par armar (realce branco e um pulso) e solte. As duas convergem, **Quero ir** nasce no ponto de encontro, **agora** e **depois** brotam dele e a frase migra para o centro. Se você soltar antes de armar, a palavra volta para a vaga dela, sem reordenar nada. Enquanto você arrasta, a composição fica parada e só se reorganiza depois.

**Tocar.** Toque em querer, depois em ir e depois em um dos dois. Tocar no fundo cancela.

**Pinça.** Repouse um dedo em querer e outro em ir e aproxime os dois até armar. Tirar um dos dedos funde. Aproximar também funciona no simulador com a tecla Option, que mostra os dois dedos, e com Shift+Option, que move o ponto médio.

**Posição na frase.** Sobre uma frase, o dedo escolhe a fresta entre as palavras e a frase se abre ali. Arraste **eu** até a ponta esquerda de **Quero ir** e sai "Eu quero ir"; na ponta direita, "Quero ir eu". Enquanto a palavra está ao alcance, a frase cresce um pouco e as vizinhas se afastam (só visualmente). Num par por toque, as setas ← → movem a fresta. Para retirar uma palavra, segure-a por 0,2 s e puxe: ela vira uma bolha própria e, se você a soltar sobre a frase, entra de novo na fresta escolhida, o que reordena.

**Desfazer.** O botão `<` desfaz dividindo o resultado. Pressionar o resultado da última fusão por 0,45 s faz o mesmo: a bolha treme cada vez mais, um som tremular cresce e a divisão termina numa nota curta.

**Sacudir.** Sacudir uma bolha durante o arrasto deriva até três palavras relacionadas, sem mudar o foco. O Undo as remove.

**Sons.** O iPad não tem háptico para o dedo, então o som faz esse papel. Há sons para fusão, divisão e erro da pinça incompatível, mais uma escala sorteada a cada arrasto, tocada ao passar pelas frestas da frase, com um snap ao entrar. A sobreposição estática fica em silêncio. O volume é baixo, os sons ficam sempre ligados e respeitam o modo silencioso.

O botão de ajustes abre a calibração da distância de aproximação. A atmosfera de fundo é só Metal. O estado e os parâmetros vivem apenas na sessão: não há SwiftData, voz nem serviço remoto.

## Código

- `TesteMetaWord/Composition.swift`: estado, gestos, fusão, Undo, foco e zonas, lidos do último léxico do motor.
- `TesteMetaWord/CompositionEngine.swift`: contrato do motor (`lexicon(for:focus:)`) e `RuleEngine`, o motor padrão e o fallback.
- `TesteMetaWord/Vocabulary.swift`: palavras iniciais, combinações e relevância (`zone`) usadas pelo `RuleEngine`.
- `TesteMetaWord/Grammar.swift`: gramática procedural de fusão. Lê `ml/vocabulary.json`, que é recurso do app e fonte do dataset (ver `SPEC.md`).
- `TesteMetaWord/Physics.swift`: física pura (repulsão, vagas por zona, nascimento, órbita), com as constantes nomeadas.
- `TesteMetaWord/ContentView.swift`: canvas, `TimelineView` como relógio da física, atmosferas, gestos e animações.
- `TesteMetaWord/ChipView.swift`: cápsula de vidro, estado armado e pulso, e a frase palavra por palavra, com a fresta aberta.
- `TesteMetaWord/PhraseLayout.swift`: molduras das palavras pelo layout de texto, fresta sob o dedo (com histerese) e alvos para retirar uma palavra.
- `TesteMetaWord/AtmosphereView.swift` e `Atmosphere.metal`: parâmetros e shader da atmosfera (faixas suaves, união luminosa das cápsulas, deformação localizada).
- `TesteMetaWord/TouchTracker.swift`: observador UIKit dos dedos na tela, sem consumir toques. É a base da pinça.
- `TesteMetaWord/SplitTension.swift`: tensão do long press (curva do tremor, síntese do som tremular, reprodução).
- `TesteMetaWord/Sfx.swift`: sons sintetizados e o player.
- `TesteMetaWord/Shake.swift`: reconhecimento da sacudida no arrasto.
- `ml/`: preparação do motor por modelo local (dataset, LoRA, avaliação). Fica fora do target do app; ver `ml/README.md`.

## Build e testes

```sh
xcodegen generate          # só ao criar ou remover arquivos
./scripts/build.sh
./scripts/test.sh          # testes de lógica, o ciclo do dia a dia (~15 s com build)
./scripts/test.sh ui       # o percurso único de interface (~25 s)
./scripts/test.sh all      # os dois, antes de integrar em main
```

O `test.sh` imprime só as falhas e o resumo, e o código de saída 0 significa aprovado. `DESTINATION='platform=iOS Simulator,id=<UDID>'` escolhe outro simulador; o padrão é o iPad Pro 13-inch (M5).

O `build.sh` compila para iPad sem assinatura, e o app fica em `build/DerivedData/Build/Products/Debug-iphoneos/TesteMetaWord.app`. Se o ambiente impedir o sandbox de macros (o projeto usa `@Observable`), rode `./scripts/build.sh 'OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox'`.

A validação mínima é build, testes de lógica e um percurso de interface básico. Não há testes nem scripts de comparação visual. Crashes e erros críticos são relatados por quem usa (ver "Validação" em `AGENTS.md`).

Versionamento: `main` guarda a base de referência, e os experimentos usam branches `exp/<nome>` com worktrees sob demanda. A integração é por merge local, sem PR obrigatório. Os comandos estão em [docs/GIT.md](docs/GIT.md).

## Histórico dos experimentos

Esta seção registra o que foi feito e medido em experimentos já integrados. Para o comportamento atual, vale o `SPEC.md`. O renderizador por gradientes, o interruptor de sons e o script `scripts/capture-atmosphere.py` foram removidos em `exp/gramatica-procedural`, e os trechos abaixo os citam como eram na época.

### Referência por gradientes

O fundo por gradientes foi salvo em `6543743`, com build aprovado, 21 testes de lógica e 3 de interface. Esse commit virou a base do experimento Metal e entrou em `main` por `4a286ee`. As capturas estão em [docs/media](docs/media): `atmosphere-{initial,armed,first-fusion,long-phrase,undo}.jpg`.

### Metal (16/10/2026)

Branch `exp/metal-atmosphere`. Um shader como preenchimento SwiftUI, atrás do Liquid Glass nativo, sem renderizador MetalKit e sem mudar o motor de composição nem a física. A comparação foi visual e funcional no simulador. Desempenho, consumo e sensação no iPad físico não foram medidos, então não há alegação de ganho de FPS ou de energia.

- **Build:** aprovado para iPadOS sem assinatura, com `default.metallib` dentro do app. O único aviso é o dos metadados de App Intents, ignorados.
- **Testes:** 23 de Swift Testing e 5 XCTest de interface passaram num simulador dedicado (iPad Pro 13-inch M5, iOS 26.4).
- **Percursos:** três fusões reais em cada renderizador, troca de modo preservando palavras, corpos e Undo, rotação e resistência superficial. A rotação passou a ser capturada com `XCUIScreen.main.screenshot()`, porque a captura do app mantinha um recorte de retrato.
- **Continuidade:** a sequência mostrou um halo deslocado enquanto o foco recém-fundido esperava a medição. A atmosfera passou a reter a geometria anterior nesse intervalo.
- **Teste instável:** numa das execuções, `focusCentersAndEachZoneSettlesOnItsOwnRingWithoutGlassBridges` falhou com 4,45 pt de distância contra um limite de 4 pt. Ele usa UUIDs e impulsos aleatórios. A física e o teste não foram alterados, a repetição isolada passou e o limite continua como estava.

A luz ficou distribuída pelo contorno do par, com queda suave e sem degraus visíveis, e o canvas se manteve contínuo nas duas orientações. O repouso mantém a referência noturna. Não rodou nenhum formatter nem linter. As capturas reduzidas estão em [docs/media/metal](docs/media/metal). Os originais, os logs e os `.xcresult` ficaram fora do repositório, na máquina do autor.

### Pinça (16/10/2026)

Branch `exp/pinca`. As regras estão no `SPEC.md` (seção "Pinça"). O `TouchTracker.swift` observa os dedos via UIKit sem consumir toques, porque o SwiftUI não informa dedos parados nem quantos estão na tela.

- **Testes:** 33 de Swift Testing, 6 deles novos em `PinchTests` (armar e confirmar, soltar abaixo do limiar, desarmar ao afastar, par incompatível só com resistência, pinça que substitui seleção ou arrasto, bolha sob o dedo), e 8 XCTest de interface, todos aprovados. Os 7 testes de interface anteriores confirmam que o observador não quebrou arrasto, soltura superficial, atmosfera, troca de renderizador nem long press.
- **Dois dedos na mesma bolha:** `testTwoFingersOnOneBubbleDoNotPinchOrSplit` faz uma pinça de cerca de 1,5 s sobre o resultado de uma fusão. Nenhuma pinça começa e o long press não divide.
- **Limite do XCTest:** `pinch(withScale:)` pousa os dois dedos na diagonal da moldura de um único elemento. Como as bolhas mudam de lugar a cada abertura, não há teste automatizado confiável da pinça entre duas bolhas. Essa é a exceção registrada à regra de validar o gesto inteiro em teste de interface.
- **Simulador:** o autor conferiu à mão, em 16/10/2026, a pinça entre duas bolhas e a divisão por long press com tremor e som.
- **Pendente no iPad físico:** dedos reais, terceiro dedo, o dedo que sobra depois da fusão e a folga entre dedos em chips largos e pequenos.
