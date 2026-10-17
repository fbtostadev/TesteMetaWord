# Handoff: atmosfera reativa com Metal

## Objetivo desta iteração

Na worktree `TesteMetaWord-wt-metal-atmosphere`, branch `exp/metal-atmosphere`, comparar um shader de luz procedural com o fundo por gradientes. A referência foi preservada no commit `6543743`, integrado a `main` em `4a286ee`. O objetivo é continuidade visual sutil durante o gesto; a avaliação desta etapa usa o simulador.

## Estado entregue

- **Foco:** é o resultado da última fusão ou, sem fusão, a palavra com mais combinações. É atraído para o centro do canvas (`Composition.focus`).
- **Zonas:** 1, combina com o foco; 2, combina com outra palavra; 3, sem combinação (`Vocabulary.zone`, `Composition.zones`). Os gaps-alvo até a superfície do foco são 30 / 116 / 202 pt, tomados pelas zonas ocupadas em ordem (zona vazia não ocupa anel).
- **Metal** (`Atmosphere.metal`): shader `[[ stitchable ]]` como `ShapeStyle`, com dithering, alfa pré-multiplicado e teto de 0,18. Três zonas analíticas usam gaps recebidos da física. O par usa distância a cápsulas e união suave (24 pt), queda de 28 pt e deformação local de até 8 pt num alcance de 160 pt.
- **Dados compartilhados:** foco, três intensidades, duas superfícies visíveis e aproximação lógica. A resistência atenua a luz e o recuo da membrana desloca a geometria. Não há buffer do vocabulário, relógio adicional ou efeito sobre o texto/vidro.
- **Calibração:** só a distância de aproximação; o relógio do canvas pausa enquanto o painel está aberto, ancorado no botão de calibração. A atmosfera é só Metal (removidos o renderizador por gradientes e o seletor).
- **Feedback luminoso:** reforço interno somente se o foco participar, par mais luminoso ao armar e atenuado pela resistência. Interpolação de foco/ocupação/dimensão em 0,24 s e feedback em 0,14 s; última geometria retida durante a saída. Camada sem interação, atrás do vidro. Sem animação autônoma.
- **Física** (`Physics.swift`, pura): repulsão abaixo de 40 pt e mola até um slot em cada zona. Os slots têm ângulos uniformes, preservam a ordem angular e usam a rotação de menor deslocamento; o raio é obtido por bisseção no gap-alvo. A física fica congelada durante calibração, arrasto, seleção, par preparado e fusão.
- **Fusão:**
  - convergência de 0,2 s;
  - o resultado nasce no ponto de encontro, por crossfade;
  - as sugestões brotam dele com impulsos radiais distintos;
  - o resultado então migra para o centro.
- **Undo:** divide o resultado, que mantém a identidade de vidro, enquanto a outra origem brota. As sugestões somem.
- **Tensão do long press** (`SplitTension.swift`, integrado de `exp/long-press-split`): durante os 0,6 s da pressão no resultado da última fusão, a bolha treme (até 2,5 pt, progresso²) e incha até 1,04×, e um som tremular sintetizado cresce. Na divisão, a nota de divisão de `Sfx.swift`. Desistir esmaece o som em ~40 ms, sem nota. Palavra indivisível: nada acontece. Áudio ambiente (respeita o modo silencioso); o iPad não tem háptico para o dedo, então o som faz esse papel.
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

## Experimento: gramática procedural (`exp/gramatica-procedural`)

Integrada a `main` em `b2806fd`.

Worktree `TesteMetaWord-wt-gramatica-procedural`. A tabela de regras escrita à mão em `Vocabulary.swift` foi substituída por `Grammar.swift`, porte da classe `Grammar` de `ml/build_dataset.py`. Ela lê `ml/vocabulary.json`, que passa a ser recurso do app (via `project.yml`) e fonte única para o app e o dataset. A API de `Vocabulary` e o contrato `CompositionEngine`/`Lexicon` não mudaram.

- **Cobertura:** 49 palavras; 4.992 frases fortes (antes, 41 pares). Entram sujeitos você/nós, negação, modais precisar/poder/gostar, verbos dormir/ver/ouvir/tomar banho, complementos, tempos hoje/amanhã, lugares e interjeições. As palavras iniciais não mudaram.
- **Fusão total:** qualquer palavra, de qualquer zona, se funde com qualquer outra, e o resultado vira o foco. A zona passa a ser a força da fusão com o foco: 1 forte (frase da gramática), 2 média (telegráfica ou reparada, “Eu brinco”), 3 fraca (coordenada, “Quero ir e comer”). `Vocabulary.Combination.strength` carrega a força; `Composition` recebe o léxico inicial por parâmetro, para testar motores que omitam pares (a pinça incompatível só existe nesse caso).
- **Paridade:** as fusões fortes mantêm os 41 resultados da tabela anterior. Quatro sugestões mudaram (ver `SPEC.md`), o que levou o percurso visual a usar Eu quero comer + **mais** no lugar de + agora; a captura “long-phrase” deixa de mostrar a Zona 1 vazia.
- **Testes:** 46 Swift Testing e 9 XCTest de interface aprovados no simulador iPad Pro 13-inch (M5) (`build/fusao-total.xcresult` e o novo `testOuterZoneWordFusesWithTheFocus`, que arrasta uma palavra da zona externa sobre o foco). Não validado no iPad físico nem por leitura das novas frases com fonoaudiólogos.
- **Divergência com `ml/`:** `vocabulary.json` ganhou `present`, `places` e `interjections`, lidos só pelo app. O dataset (`build_dataset.py`) ainda trata as fusões média e fraca como inválidas; o modelo precisa de nova rodada antes de virar `LocalModelEngine`.
- **Camadas compactas:** repulsão de 40 → 30 pt, spacing do vidro de 32 → 24 pt e anéis a 30 / 116 / 202 pt (antes 40 / 136 / 232). Zona vazia não ocupa anel: as externas se reaproximam da BubbleKey (`Physics.zoneGap(_:occupied:)`, também na atmosfera).
- **Sacudir:** `ShakeDetector` (três inversões em 0,8 s, balanços de 28 pt) deriva até três palavras de `Lexicon.related`, sem mudar o foco; Undo as remove. Ação de acessibilidade equivalente. Testes de lógica cobrem o reconhecimento, as palavras e o Undo; **o XCTest não faz arrasto com vários segmentos**, então a sacudida real fica para validação à mão.
- **Testes após camadas e sacudir:** 51 Swift Testing e 9 XCTest de interface aprovados (`build/camadas-sacudir.xcresult`).
- **Limpeza:** atmosfera só Metal (sem renderizador por gradientes, seletor na calibração nem argumento de lançamento; até compilar, o canvas fica sem atmosfera), sons sempre ligados (sem interruptor), `scripts/capture-atmosphere.py` removido e testes de interface reduzidos a um percurso básico num só lançamento (~25 s, antes ~200 s). `scripts/test.sh` roda lógica, interface ou os dois, com saída silenciosa. Validação mínima, conforme `AGENTS.md`; 51 Swift Testing e o percurso de interface aprovados.
- **Correção de sobreposição:** depois de sacudir (camada lotada) e com BubbleKey larga, palavras ficavam encostadas com ponte de vidro, porque os alvos de cada camada eram ângulos iguais sem checar espaço e a mola equilibrava a repulsão. Agora o anel é empacotado pelo espaço real, o excedente transborda para o anel seguinte e os anéis externos desviam das palavras internas (`Physics.targets`). Testes novos reproduzem os dois casos (`aCrowdedZoneOverflowsInsteadOfPinningWords`, `aWideFocusKeepsItsZonesApart`). `scripts/test.sh` deixou de usar `-quiet`, que escondia as falhas do Swift Testing, e passou a filtrar a saída.
- **Divisão após outros atos e fusão passiva:** o long press dividia só o último ato, então depois de sacudir a BubbleKey não se desmembrava. Agora `Composition.split` divide a última fusão ainda na tela em qualquer momento (o histórico guarda origens e sugestões de cada fusão). Palavras repetidas se fundem passivamente (`duplicates`, `absorbDuplicates`). Bolhas soltas voltam com força em curva suave (`Physics.Body.ramp`), e o transbordo tira primeiro as mais estreitas, mantendo as densas perto do centro.
- **Vigia de ociosidade:** a composição podia ficar congelada fora dos anéis (fusão passiva cancelada no meio deixava o par “em fusão”; arrasto cancelado pelo sistema sem `onEnded`; seleção por toque esquecida). Corrigido o primeiro; `ContentView.watchdog` limpa atos presos sem dedo na tela após 1,5 s e solta a seleção após 4 s, com retorno suave. Não coberto por teste automático; conferir à mão.
- **Raios de bolhas:** após desmembramentos em sequência as palavras brotavam do centro em poucas direções, os anéis giravam para segui-las e a palavra externa bloqueada recuava ao longo do raio, empilhando bolhas em raios estáveis. Agora ela desliza no próprio anel até um vão (`Ring.free`); teste `outerRingsInterleaveInsteadOfStackingInSpokes`.
- **Colmeia orgânica:** os alvos por anel, recalculados a cada quadro a partir das posições, davam formas diferentes a cada interação (raios, vãos). Agora `Physics.layout` calcula uma colmeia de fileiras desencontradas uma vez por mudança, independente das posições (só escolhe o espelhamento que menos move), com zonas de dentro para fora, densas junto da BubbleKey e pares de fusão forte vizinhos (cargas opostas). `Physics.step` recebe os alvos prontos; a view refaz o layout quando muda o que ele usa (`LayoutInputs`). A luz das zonas continua desenhada por anéis (`zoneGap`) e só aproxima a colmeia.
- **Reorganização local (decisão do autor, 17/10):** recalcular a colmeia inteira a cada mudança, com a nova BubbleKey no centro, fazia ~50 bolhas atravessarem a tela numa só fusão. Agora a colmeia completa só é montada na abertura, num novo canvas ou com bolha mais alta que as fileiras; depois `Physics.adapt` encaixa só as palavras novas onde nasceram, com as vizinhas da fileira abrindo espaço. A BubbleKey deixou de migrar ao centro (mudança de intenção pedida pelo autor). Long press 0,6 → 0,45 s e partida suave 0,7 → 0,45 s.
- **Gravidade suave:** só com a reorganização local, os buracos de palavras que saíram espalhavam a estrutura. `Physics.compact` desce palavras para vagas livres mais perto da BubbleKey, de dentro para fora e em saltos curtos em cascata. Apontar para o centro fixo da colmeia deixava a BubbleKey na borda após desmembramentos, com todas as palavras de um lado; o salto curto evita que a colmeia grande atravesse a tela.
- **Centralização em bloco:** a BubbleKey volta ao centro com a colmeia inteira deslizando junto (`Physics.recenter`), sem que nenhuma bolha troque de vizinho ou fileira. Restaura a intenção “o foco migra para o centro” sem o embaralhamento.
- **Em aberto (decisão da equipe):** texto das fusões fraca e média; se a zona externa deve exigir sobreposição maior; som de erro, que deixa de ocorrer com a gramática; sugestões por associação (n-gram, `NLEmbedding`).

## Experimento: inserção posicional (`exp/insercao-posicional`)

Worktree `TesteMetaWord-wt-insercao-posicional`, a partir de `exp/gramatica-procedural`. Integrada a `main` em `eb1dd58`, logo depois da gramática procedural (`b2806fd`); suíte completa aprovada nas duas branches antes de cada merge (61 e 78 Swift Testing + percurso de interface). Etapas 1–4 da proposta entregues; regras em `SPEC.md` (“Inserção posicional”).

- **Ideia:** a posição do drag sobre a BubbleKey escolhe a fresta entre palavras onde a nova entra; a frase abre espaço ao vivo e se fecha ao afastar.
- **Decisões do autor (17/10) aplicadas:** a ordem escolhida é final e a gramática só conjuga; na ordem natural, a força da fusão; fora dela, um grau mais fraca (“Quero agora ir”, média). Remoção e reordenação entram como **ato novo** no histórico (Undo continua linear, sugestões ficam); segurar parado divide, segurar e puxar uma palavra para fora remove só ela (implementado em `exp/remocao`, abaixo).
- **1. Gramática:** `Grammar.units(of:)` divide a frase em palavras do vocabulário pelas formas escritas (“para casa”, “gosto de”, “Sim,”); `Grammar.insert(_:into:at:)` insere na posição, reconjuga e pontua. Posição repetida coordena com “e” onde as gêmeas se encontram. `frame(of:)` passou a ler também frases na ordem da pessoa, para que continuem se fundindo pelas posições.
- **2. Desenho e medida:** a BubbleKey desenha palavra por palavra na mesma cápsula, nas molduras do TextKit (`PhraseLayout`); a fresta sob o dedo tem fronteira no meio de cada palavra e histerese de 10 pt, medida na frase fechada. Frase que quebra linha é desenhada inteira e usa a posição natural.
- **3. Abertura:** a fresta abre com a largura da palavra que entra, na proporção da sobreposição até armar; a cápsula alarga e a luz do foco acompanha. Ao confirmar, a palavra desliza até a fresta e o resultado nasce na BubbleKey; a física reorganiza depois pela mudança de tamanho (`adapt`/`compact`), como antes, porque a composição fica parada durante o gesto.
- **4. Acessibilidade e teste:** setas ← → e ajuste do VoiceOver (“inserir no início / depois de … / no fim”) num par por toque; toque, pinça e arrastar a própria BubbleKey começam na melhor fresta. O percurso de interface solta “eu” à esquerda e à direita da mesma BubbleKey.
- **Sacudir × fresta:** o vai e vem do dedo escolhendo a fresta disparava a sacudida. A escolha da fresta tem prioridade: enquanto `Composition.choosingGap` e por 0,4 s depois (`ShakeDetector.grace`), os balanços são esquecidos; a fresta é lida antes da sacudida em cada passo do arrasto. Teste `choosingAGapSuspendsTheShake`. Sacudida real à mão ainda pendente (o XCTest não faz zigue-zague).
- **Foco no campo da BubbleKey (pedido do autor, 17/10):** com a palavra arrastada ao alcance, a BubbleKey cresce até 1,06× e as vizinhas se afastam (18 pt + o crescimento na direção delas, até 220 pt da superfície; `Physics.makeWay`, teste `wordsAroundTheBubbleKeyStepAsideAwayFromIt`). Suaviza a intenção “a composição fica parada durante o gesto” (ONBOARDING 1.1): o afastamento é só visual, sem mover corpos nem vagas, e se desfaz ao sair. Também afasta as vizinhas do vidro da cápsula alargada. Aprovado à mão pelo autor no simulador.
- **Motor:** `Lexicon` ganhou `phrase` (palavras do foco) e `insertions` (resultado de cada palavra em cada fresta); a zona passou a ser a força da melhor fresta. Pares sem a BubbleKey continuam com `fuse`.
- **Requisito de hitbox:** molduras reais do layout de texto, divisão sem zonas mortas na altura inteira, mínimo de 44 pt (tomado das vizinhas; nas pontas, para fora da cápsula), histerese da fresta, com testes de lógica; os alvos agora servem para pegar a palavra a retirar. Interpretei “para fora da cápsula, alvo mínimo de 44 pt” como o alvo de cada palavra ter ao menos 44 pt; confirmar com o autor.
- **Verificação:** build aprovado; 78 Swift Testing (17 novos em `GrammarTests`, `InsertionTests`, `PhraseLayoutTests`) e o percurso de interface aprovados no simulador iPad Pro 13-inch (M5). **Conferido à mão pelo autor no simulador (17/10):** abertura da fresta, crescimento da BubbleKey e afastamento das vizinhas, e a prioridade sobre a sacudida, “funcionou bem”. **Ainda não conferido:** nada no iPad físico. VoiceOver e setas: teste dispensado pelo autor (17/10).
- **Próximo:** ver o experimento de remoção, abaixo.
- **Em aberto:** se pinça e toque devem também apontar fresta; texto de frases fora da ordem com fonoaudiólogos.

## Experimento: remoção na frase (`exp/remocao`)

Worktree `TesteMetaWord-wt-remocao`, a partir de `main` em `6492d3c`. Ainda **não integrado** nem commitado. Regras em `SPEC.md` (“Retirar uma palavra da frase”).

- **Ideia:** retirar uma palavra da frase da BubbleKey reaproveita o que já existe. Segurar a palavra e puxar a **retira como ato novo** (a BubbleKey fica com o resto) e a palavra vira uma **bolha comum que o dedo continua arrastando**. Soltar longe deixa a remoção; soltar sobre a BubbleKey é a inserção posicional de sempre, e é assim que se **reordena**. Não há gesto, fresta nem hitbox novos além do pouso.
- **Decisão minha, a confirmar com o autor:** o handoff dizia “segurar parado divide, segurar e puxar remove”, mas não como distinguir isso de arrastar a BubbleKey inteira (que o teste de interface e a fusão por arrasto usam). Escolhi **tempo de repouso**: o dedo precisa ficar 0,2 s (`ContentView.pickHold`) na palavra antes de mover; antes disso, o arrasto é da BubbleKey inteira; parado até 0,45 s, divide. É a única regra por tempo fora do long press e é uma constante fácil de trocar (outra opção: puxar na vertical remove, na horizontal arrasta).
- **Reordenar são dois atos** (retirar, inserir) e dois Undos; um ato único (“mover”) não foi feito. Pôr de volta no mesmo lugar reproduz a frase.
- **Gramática:** `Grammar.remove` reescreve o resto (sujeito que sobra conjuga o modal ou o verbo; interjeição mantém as vírgulas; “e” vizinho some); a palavra volta na forma do dicionário (“Quero” → `querer`). `Lexicon.removals` traz, por palavra da frase, o resto e a palavra. `Composition.removeWord(at:)` mantém o `id` e a identidade de vidro da BubbleKey, uma fusão a menos; uma palavra cujo texto já está na tela, ou o “e”, só sai.
- **Long press depois da retirada** desfaz a edição (último ato que produziu a BubbleKey), em vez de dividir a fusão original; isso muda o que “dividir” significa numa BubbleKey editada, a rever.
- **Acessibilidade:** ação “Retirar <palavra>” em cada palavra da frase (VoiceOver), alternativa sem arrastar; depois a palavra segue o toque A → B com setas.
- **Limites:** frase que quebra linha não tem palavras medidas, então não cede palavra; dois dedos não retiram; não há alternativa por toque simples sem VoiceOver; a sacudida da palavra retirada segue as regras de sempre.
- **Verificação:** build aprovado, 87 Swift Testing (9 novos em `RemovalTests`) e o percurso de interface estendido (puxar “ir” de “Quero ir”, recolocá-la à direita, dois Undos, long press), aprovados no simulador iPad Pro 13-inch (M5). **Não conferido à mão:** a sensação do limiar de 0,2 s, a convivência com o arrasto da BubbleKey inteira e com o long press, o idle da palavra retirada; nada no iPad físico. A ação “Retirar …” do VoiceOver não será testada (dispensado pelo autor).

## Experimento: escala na passagem (`exp/remocao`)

Feito sobre a remoção, na mesma branch. Regras em `SPEC.md` (“Sons de fundo”).

- **Removido:** o tom contínuo de profundidade (`DepthTone`, `DepthVoice`, `DepthSound`) e seus testes. A sobreposição estática fica em silêncio.
- **Passagem:** cada arrasto sorteia um de 5 presets de escala sobre ré (`SfxScale.presets`), sem repetir o anterior; cada troca de fresta da BubbleKey sob a palavra arrastada toca o grau correspondente (`Sfx.pass`, 0,08 s de intervalo mínimo, 4 players em rodízio para as notas se sobreporem).
- **Snap:** uma palavra que entra na BubbleKey toca tônica + quinta da escala (`Sfx.snap`) no lugar da nota de fusão. Fusões sem a BubbleKey seguem com a nota de fusão.
- **Mais discreto (a pedido):** passagem de 0,3 → 0,2 s e pico de 0,028 → 0,014, snap de 0,5 → 0,36 s e picos de 0,026/0,02 → 0,016/0,011, timbre com um só harmônico fraco (`SfxSynth.hush`), intervalo da passagem de 0,05 → 0,08 s. Ajustar por ouvido.
- **Leitura minha do pedido, a confirmar:** “passagem” = passar pelas frestas da BubbleKey, não por qualquer bolha; “snap” = a entrada na BubbleKey. Arrastar por cima de outras bolhas continua mudo. A palavra recém-retirada da frase também toca uma nota ao pousar sobre a BubbleKey (a fresta sob ela aparece de imediato).
- **Verificação:** build e 90 Swift Testing aprovados (forma pura dos sons). **Nada ouvido ainda:** o timbre das 5 escalas, o volume, se o snap soa como encaixe e se as notas da varredura incomodam em uso contínuo precisam de escuta no simulador ou no iPad.

## Pendências

- Avaliação manual da sensação do gesto e da física, do idle em uso de C.A., da membrana, do long press, do desempenho; iPad físico. Testes de VoiceOver dispensados pelo autor (17/10): o recurso fica implementado, sem validação.
- Fora desta iteração:
  - tint do vidro;
  - hierarquia visual da frase;
  - membrana em rubber band;
  - glifo do Undo;
  - ordem espacial do VoiceOver.
- Motor de IA local: seam pronto no app (`CompositionEngine`, `RuleEngine`, `Composition.refresh()`). Rodada 2 do LoRA treinada e avaliada (`ml/README.md`). Próximo: fundir/quantizar o adaptador r2 e implementar `LocalModelEngine` com MLX Swift só para fusões (validar em iPad físico).
- Prospecção de longo prazo (vocabulário aberto, dados, treino, avaliação e outros idiomas): [future-HANDOFF.md](future-HANDOFF.md).
