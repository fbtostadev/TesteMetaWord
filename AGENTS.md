# Contexto do projeto

> **Transição de equipe:** este repositório é um protótipo de design entregue a uma nova equipe. Na primeira interação com uma pessoa da equipe, ou quando pedirem contexto, siga [docs/ONBOARDING.md](docs/ONBOARDING.md) (seção 2) antes de tarefas grandes. Ele separa a intenção de design a preservar das escolhas de implementação que podem ser trocadas.

O **TesteMetaWord** é um laboratório de design e **microinterações** para um app de **Comunicação Alternativa (C.A.) no iPad**. O foco é experimentar a composição de linguagem por manipulação direta de palavras: gestos, aproximação, atração, snapping e fusão de bolhas.

A v1 implementa composição local com chips de Liquid Glass em uma grid circular de zonas de relevância, flutuação idle, fusão ao soltar, confirmação por toque, Undo e calibração. `SPEC.md` define o comportamento atual; o conceito abaixo também inclui experimentos futuros fora desta versão.

## Conceito central

- Cada palavra ou expressão ocupa um **chip em forma de cápsula**, que funciona como botão e elemento arrastável.
- **Direção visual: Liquid Glass nativo.** A intenção é construir as bolhas com as APIs de Liquid Glass do SwiftUI e customizações, explorando sua integração com aproximação, metaballs e fusão. Não substituir esse objetivo por uma simulação de vidro feita apenas com blur, transparência, gradientes ou sombras. A viabilidade e os limites das customizações devem ser verificados durante os experimentos.
- A composição é uma **grid circular orgânica**: não há linhas fixas. A palavra recém-fundida é o **centro óptico** e migra para o centro; as demais ocupam três **zonas de atmosfera** por relevância (vínculo semântico e gramatical com o foco), e a repulsão equilibra as distâncias entre as células. Quanto mais perto do foco, maior a probabilidade de fusão. Chips têm largura adequada ao texto. A referência visual apresenta cápsulas brancas, texto escuro e fundo escuro. A organização hexagonal descreve a disposição, não o formato dos botões.
- As palavras surgem do centro e a composição se expande organicamente para a periferia. Atração, gravitação leve e snapping mantêm a coesão e ajudam os elementos a encontrar posições.
- Os chips têm comportamento visual de **metaballs**: a aproximação e o contato criam uma ponte fluida entre suas superfícies, evocando uma **mitose reversa** quando se fundem.
- Arrastar ou aproximar dois elementos com um gesto de pinça pode produzir um **merge semântico**. A fusão transforma palavras em uma nova palavra ou expressão, com ajuste linguístico quando necessário.
- Exemplo: **“Querer” + “Ir” → “Quero ir”**. Após a fusão, surgem duas novas bolhas complementares ao contexto e contrastantes entre si: **“agora”** e **“depois”**, permitindo continuar a composição.

O núcleo do experimento é a relação entre movimento físico, fusão visual e composição de significado.

## Decisões de interação

- **Confirmação:** soltar com sobreposição profunda confirma o merge no arrasto. A alternativa sem arrasto usa confirmação por toque.
- **Aproximação armada:** a intenção é medida pela profundidade da sobreposição, não por tempo de permanência. Ao atingir o limiar, o par fica armado com feedback visual; a distância de aproximação é calibrável.
- **Fusão reversível:** uma geração acidental de palavra pode ser desfeita por **long press** ou pelo botão **Undo (`<`)**. A interação admite erro e oferece recuperação.
- **Motor de composição local:** combinações, sugestões, foco e zonas vêm de um `CompositionEngine`. O padrão são regras locais predefinidas (`RuleEngine`). Em preparação: um modelo de linguagem aberto e pequeno, ajustado com LoRA no Mac (`ml/`) para rodar no iPad. Nada de serviço remoto nem custo por token.
- **Limite espacial:** a composição tem um diâmetro limite e uma zona de sumiço na periferia. O comportamento exato de desaparecimento será calibrado no experimento.

## Decisões da v1

- Sobreposição profunda (45% da menor altura) arma o par; soltar armado confirma a fusão. Hover superficial recebe resistência visual ao parar de avançar; soltura sem fusão devolve a palavra à sua zona na direção em que caiu, sem reordenar. Não há dwell.
- Toque A → B → membro do par oferece alternativa sem arrasto.
- Foco, zonas de relevância (interna: combina com o foco; média: combina com outra palavra; externa: sem combinação) e física de repulsão + atração por zona posicionam as palavras. A física fica congelada durante o ato (arrasto, seleção, par preparado, fusão) e reorganiza depois. Órbitas idle sincronizadas por família mostram a origem comum. Fusão é mitose reversa; sugestões brotam do resultado (mitose). Detalhes e constantes em `SPEC.md`, `TesteMetaWord/Vocabulary.swift` e `TesteMetaWord/Physics.swift`.
- Undo usa histórico de estados completos e se mostra como divisão do resultado. Long press e ação de acessibilidade só desfazem o resultado da última fusão.
- Vocabulário e sugestões locais estão definidos em `SPEC.md`; o motor por modelo local ainda não está integrado ao app; não há voz. Cada chip guarda contagem de fusões e cresce 4% por fusão, até +24%.
- Pinça, zona de sumiço e persistência estão fora da v1.
- Parâmetros de calibração e limitações de validação constam em `SPEC.md` e `README.md`.

## Decisões em aberto para experimentos futuros

- **Gestos e recuperação:** como a pinça seleciona dois chips e qual é o alvo do long press? O Undo reverte só a última fusão ou mantém um histórico? Qual alternativa existe para quem não consegue arrastar ou usar dois dedos?
- **Vocabulário:** quais palavras aparecem inicialmente e quais combinações são válidas? As sugestões seguem oposição estrita ou alternativas contextuais contrastantes, como “agora/depois”?
- **Zona de sumiço:** qual é o diâmetro e como os chips desaparecem? Eles podem retornar? Como o Undo interage com essa zona?
- **Persistência:** o que deve ser salvo entre sessões? Síntese de voz ainda não foi definida.

Não trate esses pontos como requisitos resolvidos nem acrescente serviços remotos de IA, síntese de voz ou outras funcionalidades sem definição do experimento correspondente.

## Base técnica

- App nativo em Swift e SwiftUI, exclusivo para iPad com iPadOS 26 ou superior.
- Estado temporário em `Composition` (`@Observable`), sem persistência e sem SwiftData na v1.
- `TesteMetaWord.xcodeproj` é o projeto para abrir no Xcode; `project.yml` é sua definição em XcodeGen.
- `TesteMetaWord/ContentView.swift` contém a tela inicial.
- `ml/` prepara o motor por modelo local (Python, mlx-lm); não faz parte do target do app.

## Diretrizes para experimentos

- Mantenha cada experimento pequeno e fácil de alterar ou remover.
- Priorize a qualidade da interação: intenção do gesto, timing, continuidade do movimento e clareza do feedback.
- Preserve legibilidade e alvos de toque durante o movimento e a fusão; a dinâmica deve apoiar o uso em comunicação alternativa.
- Considere toque, Apple Pencil e teclado/trackpad quando relevantes ao experimento.
- Respeite acessibilidade, incluindo a preferência por movimento reduzido.
- Use SwiftData quando o experimento precisar persistir dados; estado temporário pode permanecer na view.
- Evite adicionar funcionalidades de produto, dependências ou arquitetura sem necessidade para o experimento solicitado.
- Ao alterar configurações do projeto, atualize `project.yml` e regenere o `.xcodeproj` para manter ambos consistentes.

## Fluxo Git

- `main` é a base de referência. Experimentos de interação usam branches `exp/<nome>`; worktrees, quando necessárias, ficam em pastas irmãs `../TesteMetaWord-wt-<nome>`.
- Correções pequenas e documentação podem entrar direto em `main`. Experimentos validados são integrados com `git merge --no-ff`, sem PR obrigatório.
- Não criar PRs, branch `develop`, hooks ou etapas de aprovação sem necessidade solicitada. Seguir [docs/GIT.md](docs/GIT.md) para comandos e encerramento de experimentos.

## Validação

Consulte `README.md` para os comandos de build, assinatura e limitações do ambiente. O script de compilação é `./scripts/build.sh`. Diferencie compilação bem-sucedida de interação validada em simulador ou iPad físico.

Ao alterar arrasto/fusão, validar o gesto inteiro (arrastar e soltar) em teste de interface, não apenas o fluxo de toques ou o estado isolado.
