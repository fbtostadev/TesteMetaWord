# Git no LAB

`main` é a base de referência para comparar os experimentos. Cada experimento
de interação usa uma branch curta `exp/<nome>`, numa worktree própria quando
for útil manter a base aberta no Xcode. Uma ou duas experiências ativas bastam.
Correções pequenas e documentação podem ser commitadas direto em `main`.

Worktree é outra pasta de trabalho do mesmo repositório: compartilha histórico,
branches e tags, mas tem arquivos e staging próprios. A mesma branch não deve
ficar aberta em duas worktrees. Não é necessário usar repositório bare nem
mover a pasta atual.

## Estrutura

```text
dev/
├── TesteMetaWord/                # main, pasta atual e base de comparação
├── TesteMetaWord-wt-snapping/    # exp/snapping, criada quando necessário
└── TesteMetaWord-wt-membrana/    # exp/membrana, outro experimento opcional
```

## Abrir um experimento

Na pasta `TesteMetaWord`, com a base atualizada e sem alterações pendentes:

```sh
git status --short --branch
git worktree add -b exp/snapping ../TesteMetaWord-wt-snapping main
cd ../TesteMetaWord-wt-snapping
open TesteMetaWord.xcodeproj
```

Troque `snapping` pelo nome do experimento. O build de cada pasta fica isolado
em seu próprio `build/`. Para listar as pastas abertas: `git worktree list`.

Faça commits pequenos por intenção, usando `área: descrição`. Revise o diff e
adicione os arquivos escolhidos explicitamente. Por exemplo, se esses forem
os arquivos alterados:

```sh
git diff
git add TesteMetaWord/Physics.swift TesteMetaWordTests/PhysicsTests.swift
git diff --cached
git commit -m "physics: ajusta atração no snapping"
```

Commits intermediários são úteis para guardar uma hipótese. Para integrar,
compile e execute os testes pertinentes conforme o README. Mudou arrasto ou
fusão? Valide também o gesto completo de arrastar e soltar em teste de interface.
Registre separadamente o que foi compilado, testado no simulador e avaliado no iPad.

## Integrar sem PR

Depois de validar e commitar o experimento, volte à pasta principal. Confira
que ela está limpa e revise o que entrará:

```sh
cd ../TesteMetaWord
git status --short --branch
git log --oneline main..exp/snapping
git diff main...exp/snapping
git merge --no-ff exp/snapping -m "lab: integra experimento de snapping"
```

O merge commit marca o experimento, mesmo quando seria possível um fast-forward.
Valide o resultado integrado antes de encerrar, especialmente se `main` avançou
durante o experimento. Conflitos podem ser resolvidos no merge ou cancelados com
`git merge --abort` antes de sua conclusão.

Com o resultado aprovado e a worktree sem alterações pendentes:

```sh
git worktree remove ../TesteMetaWord-wt-snapping
git branch -d exp/snapping
```

Guarde antes qualquer captura ou artefato ignorado que queira preservar.
Se quiser pausar uma ideia, faça commit e mantenha a branch; pode remover só a
worktree e reabri-la depois com
`git worktree add ../TesteMetaWord-wt-snapping exp/snapping`.
Não é obrigatório integrar todo experimento.

Para reverter um experimento já integrado, encontre o merge com
`git log --oneline --merges` e use `git revert -m 1 <hash-do-merge>`.
Isso cria um novo commit, preservando o histórico.

## PRs e marcos

Neste LAB solo, o padrão é merge local direto em `main`. PR é opcional para
revisão externa ou uma discussão que mereça ficar registrada. Não há branch
`develop`, aprovação obrigatória, template ou release para cada experimento.
No GitHub, não habilite exigência de PR se quiser manter esse fluxo.

Use tags descritivas só para marcos que queira reencontrar, como
`git tag -a lab-snapping-01 -m "Snapping avaliado no iPad"`, depois dessa avaliação.
Não é necessário adotar SemVer enquanto o projeto for um laboratório.

Código, testes, documentação, `project.yml`, `.xcodeproj`, datasets e métricas
JSON entram no Git. Builds, dados pessoais do Xcode, ambientes Python, logs de
treino e pesos de modelos ficam fora. Os checkpoints existentes continuam no
disco; sua preservação exige uma cópia separada.

O repositório começa local, sem remoto. Para backup, conecte depois um remoto
e envie as branches que quiser preservar; Git local sozinho não é backup.

Referências: [worktrees](https://git-scm.com/docs/git-worktree),
[merge](https://git-scm.com/docs/git-merge) e
[regras de branches no GitHub](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches).
