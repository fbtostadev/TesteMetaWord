# TesteMetaWord v1

Experimento local para iPadOS 26+, sem persistência, voz, serviço remoto ou zona de sumiço. O motor de composição é local e substituível (ver “Motor de composição”).

## Composição

Canvas escuro com cápsulas de Liquid Glass nativo em um único GlassEffectContainer (spacing 32 pt). Tint branco e texto escuro são experimentais: não substituir o material por blur ou gradientes. Cápsulas dimensionadas pelo texto e Dynamic Type, com altura mínima de 56 pt.

A disposição não é uma grade fixa: é uma grid circular organizada pela relevância ao contexto.

**Centro óptico (foco).** O foco é o resultado da fusão mais recente; sem fusão (ou após desfazer todas), é a palavra que combina com mais palavras presentes (inicialmente “querer”). O foco é atraído para o centro do canvas: o resultado nasce onde a fusão aconteceu e migra para o centro.

**Três zonas de atmosfera.** Cada outra palavra pertence a uma zona, calculada a partir do vocabulário local:

| Zona | Critério | Distância-alvo da superfície do foco |
| --- | --- | --- |
| 1 · interna | combina diretamente com o foco (vínculo semântico e gramatical forte) | 40 pt (encosta no foco) |
| 2 · média | combina com outra palavra presente, não com o foco | 136 pt (uma camada adiante) |
| 3 · externa | nenhuma combinação disponível | 232 pt |

Quanto mais perto do foco, maior a probabilidade de fusão; a interação principal acontece na zona interna. Campos elípticos de luz branca, com queda suave e transparência no interior e na borda, desenham somente as zonas ocupadas em `composition.zones`. A Zona 1 tem a maior intensidade. Se estiver vazia, o centro fica neutro mesmo com zonas externas ocupadas.

O alcance de cada campo usa `Physics.zoneGap(zone) + 68 pt` de cada lado do foco. A largura visual do foco é `altura + max(0, largura − altura) × 0,45`, mantendo frases longas proporcionais. Essa redução vale apenas para o desenho. Fundo radial noturno e vinheta suave além da Zona 3 pertencem ao canvas, independentemente da ocupação.

**Renderização comparável.** O painel de calibração oferece Metal (padrão desta branch) e Gradientes (referência de `exp/refactor-bg`). A seleção vive na view, sem persistência. Trocar o desenho preserva palavras, corpos, foco e histórico. O painel é ancorado ao botão de calibração e usa um menu nativo. Enquanto está aberto, o relógio do canvas fica pausado para comparar a luz com as palavras paradas e manter os controles estáveis. Fundo radial, vinheta e cápsulas de Liquid Glass são compartilhados.

No modo Metal, `Atmosphere.metal` fornece o preenchimento de um retângulo SwiftUI por `ShaderLibrary`, com dithering e saída branca de alfa pré-multiplicado, limitada a 0,18. As três faixas usam queda suave e gaps recebidos de `Physics.zoneGap`, sem duplicar constantes da física no shader. A CPU envia somente foco, intensidades das três zonas, duas cápsulas do par e os parâmetros de intenção. O shader é pré-compilado como `shapeStyle`; durante a preparação ou em erro, o app usa Gradientes e informa o estado no painel.

Durante o ato, a Zona 1 ganha intensidade somente se o foco participar. O par ativo recebe luz calculada pela distância às duas cápsulas, com união suave de 24 pt e queda externa de 28 pt. A proximidade controla a conexão: um par por toque distante não recebe uma ponte atravessando o canvas. A intensidade vai de 0,055 a 0,13 ao armar e é atenuada por `1 − resistance × 0,55`. A aproximação usa o gap lógico do gesto; a posição da luz usa as superfícies visíveis, incluindo o recuo da membrana.

Perto do ponto médio do par, a aproximação deforma as faixas em até 8 pt, dentro de um alcance de 160 pt. No modo Gradientes, o par mantém a luz elíptica da referência. Mudanças de foco, dimensão e ocupação têm transição de 0,24 s; feedback de 0,14 s. O par retém sua última geometria durante a saída da luz, inclusive quando a fusão remove as origens. A geometria anterior do foco permanece até a medição do novo chip, evitando uma interpolação momentânea em direção à origem do canvas. Não há pulsação, ruído animado ou relógio adicional. A atmosfera fica atrás do `GlassEffectContainer`, sem hit testing nem elementos de acessibilidade.

Cada palavra é um corpo em uma física 2D:

- **Repulsão:** superfícies de cápsulas mais próximas que 40 pt se repelem como molas. Como 40 pt é maior que o spacing de 32 pt, não há ponte de vidro em repouso. Quando uma zona lota, a repulsão empurra o excedente para fora.
- **Atração por zona:** uma mola leva cada palavra à distância-alvo da sua zona, na direção em que ela já está; o foco é puxado para o centro. Palavras de uma mesma zona se espalham em volta do foco pela repulsão.
- **Amortecimento:** o grosso do movimento acontece em cerca de 0,4 s, com leve elasticidade; o assentamento completo leva cerca de 1 s.
- **Física só fora do ato:** enquanto há arrasto, seleção, par preparado ou fusão em andamento, a composição fica congelada (só a flutuação idle continua). Com a calibração aberta, o relógio inteiro pausa, incluindo a flutuação. Repulsão, atração e reorganização atuam depois — principalmente após a fusão.
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

Combinações adicionais locais incluem eu + querer, querer + brincar, sujeito eu nas intenções e água/suco após querer beber. Pares não definidos não geram texto arbitrário. Sugestões já presentes não são duplicadas. Palavras sem combinação continuam manipuláveis.

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

As sugestões brotam de dentro do resultado: nascem no mesmo ponto, com escala reduzida, e recebem impulsos radiais em direções distintas e intensidades levemente diferentes. A ponte de vidro se estica e se rompe enquanto elas se afastam. Em seguida, o resultado vira o novo foco e migra para o centro; as zonas são recalculadas e cada palavra busca sua nova atmosfera — sugestões complementares na zona interna, palavras que perderam o vínculo para fora.

Cada chip registra a quantidade acumulada de fusões: resultado = contagem A + contagem B + 1. A escala de fonte e cápsula cresce 4% por fusão, limitada a +24%; a largura continua limitada ao canvas e pode quebrar texto em linhas.

## Motor de composição

Combinações, sugestões, foco e zonas vêm de um motor (`CompositionEngine`), consultado de forma assíncrona após cada mudança do conjunto de palavras (abertura, fusão, Undo). Ele recebe as palavras presentes e o foco atual (resultado da última fusão, ou nenhum) e devolve um léxico:

- **fusões conhecidas:** para pares de palavras presentes, o resultado e duas sugestões complementares e contrastantes;
- **foco:** o informado, ou, sem fusão, a palavra que o motor considera mais geradora;
- **zonas:** 1, 2 ou 3 para cada outra palavra, por relevância ao foco.

Os gestos leem apenas o último léxico aplicado, de forma síncrona: um par só arma se a fusão já for conhecida. O cache de fusões vale para a sessão inteira e é indexado pelo texto, de modo que o Undo reencontra fusões já calculadas. Um léxico que chega depois de o conjunto de palavras mudar é descartado.

O motor padrão é `RuleEngine`, que usa as regras locais da tabela acima, responde imediatamente e serve de fallback. Um motor por modelo de linguagem local pequeno, ajustado com LoRA, está em preparação em `ml/` (ver `ml/README.md`); ainda não está integrado ao app.

## Undo

Merge consome as origens, cria resultado e sugestões e guarda o estado anterior completo. Undo (<) restaura um merge de cada vez, incluindo identidades, fases e contagens. Visualmente, o resultado se divide: a origem que compartilha sua identidade de vidro nasce no lugar dele, a outra sai com impulso, e as sugestões encolhem e somem. O foco volta a ser o resultado anterior (ou a palavra com mais combinações) e as zonas se recompõem. Long press de 0,6 s somente no resultado da última fusão faz o mesmo; ação equivalente disponível à acessibilidade.

### Tensão antes da divisão (long press)

Enquanto o dedo segura o resultado da última fusão (a bolha mestre divisível), a bolha acumula tensão durante os 0,6 s do long press:

- **Tremor visual:** deslocamento trêmulo com amplitude crescente (progresso², até 2,5 pt) e leve inchaço até 1,04×. A órbita idle para nessa bolha enquanto ela é pressionada.
- **Som tremular:** tom grave e suave com tremolo cuja frequência e volume crescem até o fim do long press.
- **Estouro:** ao completar 0,6 s, um estalo curto (cerca de 90 ms, timbre de bolha) toca no mesmo instante da divisão, que segue o Undo descrito acima.
- **Desistência:** soltar antes de 0,6 s ou começar a arrastar encerra tremor e som em cerca de 40 ms, sem estouro e sem mudança na composição.
- **Indivisível:** segurar uma bolha que não é o resultado da última fusão não produz tensão.
- O som usa a categoria de áudio ambiente: respeita o modo silencioso e se mistura a outros áudios. Os sons são sintetizados no app (`SplitTension.swift`), sem arquivos de áudio.
- **Háptico:** o iPad não tem Taptic Engine, então o dedo não sente háptico; o som substitui esse retorno. Háptico fica pendente até haver um dispositivo-alvo que vibre.

## Movimento reduzido

Sem órbita, impulso, pulso ou recuo espacial. Cada mudança calcula o equilíbrio de uma vez; palavras surgem e somem por dissolve. Os campos de atmosfera atualizam posição, dimensão e intensidade sem interpolação, inclusive durante fusão e Undo. O long press não treme nem incha a bolha; o som de tensão e o estouro permanecem. Na pinça, as bolhas seguem os dedos sem recuo de membrana.

## Calibração

Popover com escolha Metal/Gradientes, indicação do renderizador ativo e distância de aproximação 8–60 pt (default 24). Alterações cancelam a interação atual. Valores apenas em memória.

## Validação

Swift Testing: vocabulário, confirmação, armar/desarmar, cancelamento, Undo, foco e zonas de relevância, física (foco no centro, zonas ordenadas, ausência de pontes em repouso, nascimento) e órbita. Testes de interface arrastam e soltam sobre alvos reais, observam o resultado sem toque adicional e conferem Undo, soltura superficial e long press (divide o resultado; não divide uma palavra indivisível). A pinça é testada na lógica (armar, desarmar, soltar, par incompatível, bolha sob o dedo) e, na interface, com dois dedos reais sobre a mesma bolha (sem pinça nem divisão); o XCTest não posiciona dois dedos em elementos diferentes, então a pinça entre duas bolhas é validada à mão no simulador e no iPad. A curva do tremor e a forma dos sons são testadas como funções puras; o que se ouve e se sente exige escuta no simulador ou no iPad. Nos dois modos, o percurso eu + querer → Eu quero + comer → Eu quero comer + agora → Eu quero comer agora registra o estado inicial, a primeira fusão, a frase com Zona 1 vazia e Undo. Durante o primeiro arrasto, XCTest mantém 60% de sobreposição e a pressão por 8 s para captura externa do estado armado por `simctl` (`scripts/capture-atmosphere.py`). A comparação na mesma sessão verifica preservação dos corpos, composição e Undo; rotação verifica o canvas com frase longa. A soltura superficial inclui pressão mantida para captura da resistência. Build e testes não provam a sensação da física nem o desempenho no iPad físico.
