# TesteMetaWord v1

Experimento local para iPadOS 26+, sem persistência, voz, serviço remoto ou zona de sumiço. O motor de composição é local e substituível (ver “Motor de composição”).

## Composição

Canvas escuro com cápsulas de Liquid Glass nativo em um único GlassEffectContainer (spacing 24 pt, `Physics.glassSpacing`). Tint branco e texto escuro são experimentais: não substituir o material por blur ou gradientes. Cápsulas dimensionadas pelo texto e Dynamic Type, com altura mínima de 56 pt.

A disposição não é uma grade fixa: é uma grid circular organizada pela relevância ao contexto.

**Centro óptico (foco).** O foco é o resultado da fusão mais recente; sem fusão (ou após desfazer todas), é a palavra com mais fusões fortes entre as presentes (inicialmente “querer”). Na abertura o foco fica no centro do canvas. Depois, o resultado nasce e fica onde a fusão aconteceu: a composição se reorganiza só em volta da mudança (ver *Colmeia orgânica*), sem levar o foco ao centro, o que moveria todas as bolhas.

**Três zonas de atmosfera.** Toda palavra se funde com qualquer outra, de qualquer zona; o resultado vira o novo foco. A zona de cada palavra é a força da sua fusão com o foco:

| Zona | Critério | Distância-alvo da superfície do foco |
| --- | --- | --- |
| 1 · interna | fusão forte: forma uma frase da gramática (“Quero ir”) | 30 pt (encosta no foco) |
| 2 · média | fusão média: as posições se encaixam, mas a frase é telegráfica ou reparada (“Eu brinco”, “Dor, aqui”) | 116 pt (uma camada adiante) |
| 3 · externa | fusão fraca: as posições colidem e os textos se coordenam (“Quero ir e comer”) | 202 pt |

As distâncias valem com as três zonas ocupadas. **Zona vazia não ocupa anel:** as zonas ocupadas, em ordem, tomam os anéis 30 / 116 / 202 pt. Sem palavras na zona 1, a zona 2 se reaproxima até 30 pt da BubbleKey; só a zona 3 ocupada fica a 30 pt. A luz de cada zona mantém a intensidade da sua força e acompanha o anel em 0,24 s.

Quanto mais perto do foco, maior a probabilidade de fusão; a interação principal acontece na zona interna. Campos elípticos de luz branca, com queda suave e transparência no interior e na borda, desenham somente as zonas ocupadas em `composition.zones`. A Zona 1 tem a maior intensidade. Se estiver vazia, o centro fica neutro mesmo com zonas externas ocupadas.

O alcance de cada campo usa `Physics.zoneGap(zone) + 68 pt` de cada lado do foco. A largura visual do foco é `altura + max(0, largura − altura) × 0,45`, mantendo frases longas proporcionais. Essa redução vale apenas para o desenho. Fundo radial noturno e vinheta suave além da Zona 3 pertencem ao canvas, independentemente da ocupação.

**Renderização.** A atmosfera é só Metal: `Atmosphere.metal` fornece o preenchimento de um retângulo SwiftUI por `ShaderLibrary`, com dithering e saída branca de alfa pré-multiplicado, limitada a 0,18. As três faixas usam queda suave e gaps recebidos de `Physics.zoneGap`, sem duplicar constantes da física no shader. A CPU envia somente foco, intensidades das três zonas, duas cápsulas do par e os parâmetros de intenção. O shader é pré-compilado como `shapeStyle`; até compilar (ou se falhar), o canvas fica sem atmosfera.

Durante o ato, a Zona 1 ganha intensidade somente se o foco participar. O par ativo recebe luz calculada pela distância às duas cápsulas, com união suave de 24 pt e queda externa de 28 pt. A proximidade controla a conexão: um par por toque distante não recebe uma ponte atravessando o canvas. A intensidade vai de 0,055 a 0,13 ao armar e é atenuada por `1 − resistance × 0,55`. A aproximação usa o gap lógico do gesto; a posição da luz usa as superfícies visíveis, incluindo o recuo da membrana.

Perto do ponto médio do par, a aproximação deforma as faixas em até 8 pt, dentro de um alcance de 160 pt. Mudanças de foco, dimensão e ocupação têm transição de 0,24 s; feedback de 0,14 s. O par retém sua última geometria durante a saída da luz, inclusive quando a fusão remove as origens. A geometria anterior do foco permanece até a medição do novo chip, evitando uma interpolação momentânea em direção à origem do canvas. Não há pulsação, ruído animado ou relógio adicional. A atmosfera fica atrás do `GlassEffectContainer`, sem hit testing nem elementos de acessibilidade.

Cada palavra é um corpo em uma física 2D:

- **Repulsão:** superfícies de cápsulas mais próximas que 30 pt se repelem como molas. Como 30 pt é maior que o spacing de 24 pt, não há ponte de vidro em repouso. A repulsão é só uma rede de segurança; quem garante o espaço em repouso é a colmeia:
- **Colmeia orgânica:** na abertura (e quando o canvas muda de tamanho, ou surge uma bolha mais alta que as fileiras) a composição inteira é montada num só padrão: a BubbleKey no centro e as palavras em fileiras de cápsulas a 30 pt umas das outras, com as fileiras ímpares divididas no centro, desencontradas meia célula como favos; zona por zona (a interna primeiro) e das mais largas às mais estreitas, cada palavra toma a vaga livre mais próxima do centro (`Physics.layout`).
- **Reorganização local:** depois disso cada bolha mantém a sua vaga e as fileiras ficam fixas (`Physics.Grid`). Numa fusão, desmembramento, agitação ou Undo, cada palavra nova nasce onde a mudança aconteceu e ocupa o lugar livre mais próximo — ou abre um lugar ali, empurrando para fora só as vizinhas da mesma fileira, o que perturbar menos. Bolhas longe da mudança não se movem (`Physics.adapt`).
- **Gravidade suave:** buracos deixados por palavras que saíram não espalham a estrutura. Depois de cada mudança, de dentro para fora, uma palavra com uma vaga livre pelo menos 30 pt mais perto do centro da colmeia, a um salto de até 220 pt, desce para ela, e a vaga que deixa fica para a próxima. A gravidade aponta para o centro fixo da colmeia (não para a BubbleKey, que muda de lugar), então uma colmeia sem buracos fica parada; a BubbleKey mantém a sua vaga (`Physics.compact`).
- **Cargas opostas:** uma palavra prefere a vaga vizinha de uma palavra já posicionada com que forma frase completa (fusão forte); pares complementares ficam lado a lado.
- **Reordenação suave:** cada palavra cuja vaga mudou parte para a nova com a curva do retorno suave; a repulsão só protege o caminho.
- **Vigia de ociosidade:** a composição nunca fica congelada. Sem nenhum dedo na tela, um ato deixado pela metade (arrasto ou pinça cujo fim não chegou, fusão que não terminou) é limpo após 1,5 s; uma seleção por toque esperando o par deixa de segurar a física após 4 s e continua selecionada (um novo toque volta a segurar). Nos dois casos as palavras voltam aos poucos, com a curva do retorno suave.
- **Retorno suave:** uma bolha solta sem fundir (arrasto, pinça ou sacudida), mesmo nas extremidades, volta à sua vaga na colmeia com a força crescendo em curva suave por 0,45 s: sai devagar, acelera e assenta, sem estalo.
- **Amortecimento:** o grosso do movimento acontece em cerca de 0,4 s, com leve elasticidade; o assentamento completo leva cerca de 1 s.
- **Física só fora do ato:** enquanto há arrasto, seleção, par preparado ou fusão em andamento, a composição fica congelada (só a flutuação idle continua). Com a calibração aberta, o relógio inteiro pausa, incluindo a flutuação. A reorganização na colmeia acontece depois — principalmente após a fusão.
- **Flutuação idle:** cada palavra descreve uma órbita elíptica de cerca de 4 pt com período de 6 s. Todas compartilham o período; a fase é herdada da origem. O resultado de uma fusão mantém a fase da primeira origem, e cada sugestão segue com um atraso fixo, de modo que uma família flutua em sincronia, como uma onda. A órbita para na palavra arrastada, selecionada, armada ou em fusão.

A ordem do array não define posição. Em texto grande, o canvas cresce verticalmente e admite rolagem.

Inicialmente: querer (foco), ir, comer, beber, eu, brincar, que brotam do centro ao abrir. Pares não ordenados:

| Origens | Resultado | Sugestões |
| --- | --- | --- |
| querer + ir | Quero ir | agora / depois |
| querer + comer | Quero comer | mais / menos |
| querer + beber | Quero beber | água / suco |
| Quero ir + agora | Quero ir agora | perto / longe |
| Quero ir + depois | Quero ir depois | hoje / amanhã |

As combinações vêm de uma **gramática procedural** (`TesteMetaWord/Grammar.swift`) lida de `ml/vocabulary.json`, o mesmo arquivo que gera o dataset do modelo. Uma frase é uma moldura de posições, `[interjeição,] [sujeito] [não] [modal] [verbo] [complemento | quantidade] [tempo] [lugar]`, e cada palavra ocupa uma posição:

- **sujeitos:** eu, você, nós; **negação:** não; **modais:** querer, precisar, poder, gostar (“gosto de”);
- **verbos:** ir, comer, beber, brincar, dormir, ver, ouvir, tomar banho, cada um com seus complementos; comer e beber aceitam quantidade (mais, menos);
- **tempos:** agora, depois, hoje, amanhã;
- **lugares:** aqui, ali, perto, longe; **interjeições:** sim, obrigado, ajuda, dor.

Quaisquer dois textos diferentes se fundem, com uma de três forças:

1. **Forte:** as posições não colidem e a moldura é uma frase da gramática do dataset: tem modal, não tem interjeição nem lugar, e complemento ou tempo exigem verbo, com complemento próprio desse verbo. Duas frases também se fundem assim (“Eu quero” + “Comer agora” → “Eu quero comer agora”).
2. **Média:** as posições não colidem, mas a frase sai do padrão. Sem modal, o verbo se conjuga para o sujeito explícito (“eu” + “brincar” → “Eu brinco”) ou fica no infinitivo (“Comer agora”); modal sem verbo aceita complemento ou tempo (“Quero agora”, “Gosto de água”); complemento de outro verbo é aceito (“Quero beber pão”); lugar vem no fim (“Quero ir longe”); interjeição prefixa com vírgula (“Sim, quero ir”). O resultado continua com suas posições e pode virar forte depois.
3. **Fraca:** as posições colidem ou um texto já é resultado fraco. Os dois se coordenam com “e” (“Quero comer” + “beber” → “Quero comer e beber”; “Quero ir agora” + “depois” → “Quero ir agora e depois”). Lê primeiro a interjeição (com vírgula), depois o resultado fraco anterior, depois a ordem das posições. Tempo, lugar ou complemento após um resultado fraco entram sem “e” (“Quero comer e beber agora”).

Sem sujeito, a frase fica na primeira pessoa; o sujeito conjuga o modal (“nós” + “Não preciso” → “Nós não precisamos”). As sugestões preenchem o que falta: após sujeito e modal, ir/brincar; após negação, ir/comer; após o verbo, as do verbo; após complemento ou quantidade, agora/depois; após o tempo, perto/longe ou hoje/amanhã em ir, aqui/ali nos demais. Na fusão fraca, sugere a frase que vem primeiro.

As fusões fortes reproduzem as 41 regras da tabela anterior. Quatro sugestões mudaram para seguir o verbo também com sujeito: Eu quero + comer → mais/menos; Eu quero ir + agora → perto/longe; Eu quero ir + depois → hoje/amanhã. A conjugação sem modal (`present`), os lugares e as interjeições estão em `ml/vocabulary.json`, mas o dataset do modelo (`ml/build_dataset.py`) ainda só conhece as fusões fortes. Sugestões já presentes não são duplicadas.

O par incompatível continua previsto para motores que omitam um par (por exemplo, um modelo local); com a gramática, só textos iguais não se fundem.

## Gestos e recuperação

Arrastar acompanha o dedo; as demais palavras ficam paradas onde estão. A distância entre superfícies determina o alvo válido mais próximo (zona de aproximação inicial: 24 pt).

Quando a penetração entre superfícies atinge 45% da menor altura das duas cápsulas (25,2 pt em chips de 56 pt), o par fica **armado**: realce branco e um pulso curto. Soltar armado confirma a fusão imediatamente. Contato superficial nunca arma.

Antes do limiar, ficar 0,25 s sem avançar pelo menos 3,5% da altura menor aumenta a resistência ao longo de 0,3 s: a superfície arrastada recua até cerca de 36 pt de separação e recebe contorno mais definido; o dedo continua medindo a intenção. Retomar o avanço libera a resistência. Recuar abaixo do limiar desarma.

Soltar sem fusão libera a física: a palavra volta para a sua zona na direção em que foi solta, e a repulsão abre espaço. Não há reordenação nem retorno a uma grade.

Sem arrasto: tocar A, tocar B compatível e tocar o par novamente confirma. O par preparado fica armado no lugar, sem se mover. B incompatível passa a ser a seleção inicial. Toque repetido na seleção a cancela. Tocar no fundo, Escape, abrir calibração, redimensionar o canvas ou iniciar outro arrasto cancela. Botões permitem ativação por VoiceOver, teclado e trackpad.

### Pinça (dois dedos)

Com uma mão livre, um dedo repousado sobre cada uma de duas bolhas diferentes seleciona o par; não é preciso mover para começar. Cada bolha segue o seu dedo pelo deslocamento desde o pouso; a composição fica parada, como no arrasto. Se um arrasto já estava em curso e o segundo dedo pousa em outra bolha, ele vira pinça sem salto.

Armar, desarmar e resistência usam a mesma medida do arrasto, agora entre as duas bolhas em movimento: 45% de penetração da menor altura arma; recuar abaixo disso desarma. O primeiro dedo que sai encerra a pinça: armado, as duas convergem e fundem como no arrasto; sem armar, voltam às suas zonas. O dedo que ficou é ignorado até sair (não vira arrasto nem toque).

Par incompatível nunca arma: as bolhas seguem os dedos, e com as superfícies em contato a membrana resiste — as duas recuam simetricamente até cerca de 36 pt de separação, com contorno mais definido.

No máximo duas bolhas: um terceiro dedo é ignorado; dois dedos na mesma bolha ou um dedo no fundo não iniciam pinça, e o gesto de um dedo segue normal. Com dois dedos na tela não há tensão nem divisão por long press; o segundo dedo cancela a tensão em curso (o som esmaece, sem estalo). A pinça é opcional: arrasto com um dedo e toque A → B continuam como alternativas.

## Fusão (mitose reversa) e sugestões (mitose)

Após confirmar, as origens convergem por 0,2 s ao ponto médio. O resultado nasce nesse ponto, preservando a identidade de vidro da primeira origem; os textos das origens se dissolvem enquanto o texto do resultado surge, sem cápsula vazia. Gestos ficam bloqueados só durante a convergência.

As sugestões brotam de dentro do resultado: nascem no mesmo ponto, com escala reduzida, e recebem impulsos radiais em direções distintas e intensidades levemente diferentes. A ponte de vidro se estica e se rompe enquanto elas se afastam. Em seguida, o resultado vira o novo foco no lugar das origens, as sugestões ocupam as vagas livres mais próximas e só as vizinhas abrem espaço; as zonas são recalculadas e a luz das atmosferas acompanha o novo foco.

## Sacudir (derivação)

Sacudir uma bolha durante o arrasto deriva até três palavras relacionadas, sem consumir a bolha. O reconhecimento (`ShakeDetector`) exige três inversões de direção, em qualquer eixo, dentro de 0,8 s, cada balanço com pelo menos 28 pt; um arrasto comum, mesmo com correção, não sacode. A bolha solta onde está, as palavras brotam dela como as sugestões de uma fusão (mitose) e o resto do arrasto é ignorado até o dedo sair. Toca a nota de divisão; sem palavra para derivar, o erro.

As palavras vêm do motor (`Lexicon.related`; na gramática, `Grammar.related`): primeiro as posições logo depois da última que a bolha preenche (a continuação natural), depois as anteriores; dentro de cada posição, as que formam frase completa. Ignora palavras presentes e posições já preenchidas. Exemplos: comer → pão / fruta / biscoito; Quero ir → para casa / ao banheiro / à escola; agora → aqui / ali / perto; querer, com as palavras iniciais na tela → dormir / ouvir / tomar banho.

A derivação não muda o foco e entra no histórico: Undo (<) remove as palavras derivadas. O long press continua dividindo a BubbleKey depois dela. Ação de acessibilidade “Derivar palavras relacionadas” em cada bolha oferece o mesmo sem sacudir.

## Fusão passiva

A tela nunca mostra a mesma palavra duas vezes. Se um ato traz uma palavra que já está na tela (por exemplo, a divisão devolve “ir” depois que uma agitação derivou outro “ir”), cerca de 0,45 s depois do brotamento a repetida desliza 0,25 s até a gêmea e se dissolve nela, sem som. Fica a gêmea que já estava na tela (ou o resultado mais recente), com a maior contagem de fusões das duas. A fusão passiva faz parte do ato que criou a repetição: um Undo desfaz os dois.

Cada chip registra a quantidade acumulada de fusões: resultado = contagem A + contagem B + 1. A escala de fonte e cápsula cresce 4% por fusão, limitada a +24%; a largura continua limitada ao canvas e pode quebrar texto em linhas.

## Motor de composição

Combinações, sugestões, foco e zonas vêm de um motor (`CompositionEngine`), consultado de forma assíncrona após cada mudança do conjunto de palavras (abertura, fusão, Undo). Ele recebe as palavras presentes e o foco atual (resultado da última fusão, ou nenhum) e devolve um léxico:

- **fusões conhecidas:** para pares de palavras presentes, o resultado e duas sugestões complementares e contrastantes;
- **foco:** o informado, ou, sem fusão, a palavra que o motor considera mais geradora;
- **zonas:** 1, 2 ou 3 para cada outra palavra, por relevância ao foco.

Os gestos leem apenas o último léxico aplicado, de forma síncrona: um par só arma se a fusão já for conhecida. O cache de fusões vale para a sessão inteira e é indexado pelo texto, de modo que o Undo reencontra fusões já calculadas. Um léxico que chega depois de o conjunto de palavras mudar é descartado.

O motor padrão é `RuleEngine`, que usa as regras locais da tabela acima, responde imediatamente e serve de fallback. Um motor por modelo de linguagem local pequeno, ajustado com LoRA, está em preparação em `ml/` (ver `ml/README.md`); ainda não está integrado ao app.

## Undo

Merge consome as origens, cria resultado e sugestões e guarda o estado anterior completo. Undo (<) restaura um merge de cada vez, incluindo identidades, fases e contagens. Visualmente, o resultado se divide: a origem que compartilha sua identidade de vidro nasce no lugar dele, a outra sai com impulso, e as sugestões encolhem e somem. O foco volta a ser o resultado anterior (ou a palavra com mais combinações) e as zonas se recompõem. Long press de 0,45 s somente no resultado da última fusão ainda na tela faz o mesmo, mesmo que outros atos tenham vindo depois (sacudir, outra divisão): nesse caso as origens voltam no lugar do resultado, as sugestões que restaram dessa fusão saem, as palavras posteriores ficam, e a divisão vira um ato próprio, desfeito por um Undo; ação equivalente disponível à acessibilidade.

### Tensão antes da divisão (long press)

Enquanto o dedo segura o resultado da última fusão (a bolha mestre divisível), a bolha acumula tensão durante os 0,45 s do long press:

- **Tremor visual:** deslocamento trêmulo com amplitude crescente (progresso², até 2,5 pt) e leve inchaço até 1,04×. A órbita idle para nessa bolha enquanto ela é pressionada.
- **Som tremular:** tom grave e suave com tremolo cuja frequência e volume crescem até o fim do long press.
- **Divisão:** ao completar 0,45 s, a nota de divisão (ver *Sons de fundo*) toca no mesmo instante da divisão, que segue o Undo descrito acima.
- **Desistência:** soltar antes de 0,45 s ou começar a arrastar encerra tremor e som em cerca de 40 ms, sem estouro e sem mudança na composição.
- **Indivisível:** segurar uma bolha que não é o resultado da última fusão não produz tensão.
- O som usa a categoria de áudio ambiente: respeita o modo silencioso e se mistura a outros áudios. Os sons são sintetizados no app (`SplitTension.swift` e `Sfx.swift`), sem arquivos de áudio nem serviço remoto.
### Sons de fundo

Os sons são discretos por princípio: acompanham a interação sem chamar atenção em quem usa o app o dia inteiro. Por isso só os momentos raros, que mudam algo, têm som. Gestos frequentes (tocar, arrastar, armar) ficam em silêncio e têm feedback só visual. A única exceção é o tom de profundidade, descrito abaixo.

- **Fusão:** uma nota grave e macia (ré, 0,3 s) ao confirmar.
- **Divisão:** a mesma nota descendo (0,25 s), no Undo pelo botão `<` e na divisão por long press.
- **Erro:** um único toc surdo (0,16 s, sem sobretons) quando uma pinça incompatível encosta e a membrana resiste. O toque A → B incompatível não soa, pois só troca a seleção.
- **Tom de profundidade:** enquanto um par compatível se sobrepõe (arrasto ou pinça), um tom contínuo acompanha a profundidade da sobreposição (0 a 1, armando em 0,45). Silencioso com as bolhas separadas ou só encostadas; sobe de ré (293 Hz) até lá (440 Hz), a quinta da fusão, e de volume até 0,035. Suavizado em cerca de 30 ms e some ao afastar, soltar ou cancelar. Par incompatível não soa (só o erro). Gerado em tempo real (`DepthVoice`), em thread de áudio sem isolamento de ator.
- Nível baixo: pico de 0,03–0,04 por nota, tremor em até 0,09. Intervalo mínimo entre repetições de 0,4 s (fusão e divisão) e 1 s (erro). Escala pentatônica de ré em registro grave, sem harmônicos agudos.
- Sons sempre ligados; respeitam o modo silencioso do iPad (sessão de áudio ambiente).
- Sons sintetizados por funções puras (`SfxSynth`); a sensação continua exigindo escuta no simulador ou no iPad.

- **Háptico:** o iPad não tem Taptic Engine, então o dedo não sente háptico; o som substitui esse retorno. Háptico fica pendente até haver um dispositivo-alvo que vibre.

## Movimento reduzido

Sem órbita, impulso, pulso ou recuo espacial. Cada mudança calcula o equilíbrio de uma vez; palavras surgem e somem por dissolve. Os campos de atmosfera atualizam posição, dimensão e intensidade sem interpolação, inclusive durante fusão e Undo. O long press não treme nem incha a bolha; o som de tensão e o estouro permanecem. Na pinça, as bolhas seguem os dedos sem recuo de membrana.

## Calibração

Popover com a distância de aproximação 8–60 pt (default 24). Enquanto está aberto, o relógio do canvas fica pausado. Alterações cancelam a interação atual. Valores apenas em memória.

## Validação

Validação mínima: build, testes de lógica (`./scripts/test.sh`) e, antes de integrar, o percurso de interface básico (`./scripts/test.sh ui`: soltura rasa, arrastar e soltar, fusão da zona externa, Undo, long press). Não criar testes nem scripts que comparem renderizadores, flags ou capturas no simulador; crashes e erros críticos são relatados pela pessoa usuária.

- **Swift Testing:** vocabulário e gramática (fusões fortes contra a tabela anterior, as três forças), confirmação, armar/desarmar, cancelamento, Undo, foco e zonas, física (foco no centro, anéis, camadas que se reaproximam, ausência de pontes em repouso, nascimento), órbita, pinça (armar, desarmar, par incompatível), sacudir (reconhecimento, palavras derivadas, Undo) e a forma pura dos sons e do tremor.
- **Interface (XCTest):** um percurso num só lançamento do app: soltura rasa sem fusão, arrastar e soltar, fusão de uma palavra da zona externa com o foco, Undo e long press que divide o resultado. Espera a física assentar em vez de pausas fixas.
- **À mão:** pinça entre duas bolhas e sacudida real (o XCTest não posiciona dois dedos em bolhas diferentes nem faz arrasto em zigue-zague); sensação, sons e desempenho no iPad físico.
