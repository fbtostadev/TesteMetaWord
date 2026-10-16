# TesteMetaWord v1

Experimento local para iPadOS 26+, sem persistência, voz, serviço remoto, pinça ou zona de sumiço. O motor de composição é local e substituível (ver “Motor de composição”).

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

Quanto mais perto do foco, maior a probabilidade de fusão; a interação principal acontece na zona interna. Três halos brancos muito sutis, em forma de cápsula e concêntricos ao foco, desenham as atmosferas (não simulam vidro).

Cada palavra é um corpo em uma física 2D:

- **Repulsão:** superfícies de cápsulas mais próximas que 40 pt se repelem como molas. Como 40 pt é maior que o spacing de 32 pt, não há ponte de vidro em repouso. Quando uma zona lota, a repulsão empurra o excedente para fora.
- **Atração por zona:** uma mola leva cada palavra à distância-alvo da sua zona, na direção em que ela já está; o foco é puxado para o centro. Palavras de uma mesma zona se espalham em volta do foco pela repulsão.
- **Amortecimento:** o grosso do movimento acontece em cerca de 0,4 s, com leve elasticidade; o assentamento completo leva cerca de 1 s.
- **Física só fora do ato:** enquanto há arrasto, seleção, par preparado ou fusão em andamento, a composição fica congelada (só a flutuação idle continua). Repulsão, atração e reorganização atuam depois — principalmente após a fusão.
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

## Movimento reduzido

Sem órbita, impulso, pulso ou recuo espacial. Cada mudança calcula o equilíbrio de uma vez; palavras surgem e somem por dissolve.

## Calibração

Popover com distância de aproximação 8–60 pt (default 24). Alterações cancelam a interação atual. Valores apenas em memória.

## Validação

Swift Testing: vocabulário, confirmação, armar/desarmar, cancelamento, Undo, foco e zonas de relevância, física (foco no centro, zonas ordenadas, ausência de pontes em repouso, nascimento) e órbita. Testes de interface devem arrastar e soltar sobre um alvo real e observar o resultado sem toque adicional, além de conferir Undo e a soltura superficial. Build e testes não provam a ponte fluida, a sensação da física nem o desempenho; isso requer simulador ou iPad físico.
