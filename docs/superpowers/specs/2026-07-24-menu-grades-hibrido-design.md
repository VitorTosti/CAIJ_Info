# Menu de grades hibrido

## Objetivo

Melhorar a aparencia e a leitura do seletor de grades no cadastro de OS sem alterar as opcoes, os valores enviados ao servidor ou o restante da composicao da janela.

## Aparencia

- O menu permanece escuro e alinhado ao estilo atual do aplicativo.
- A margem branca reservada para imagens e marcadores nativos sera removida.
- A largura do menu acompanha o card `REFERENCIA`.
- Os itens terao altura, alinhamento e espacamento consistentes.
- Uma barra lateral estreita identifica visualmente cada grupo:
  - Grade A: verde.
  - Grade B: amarelo.
  - Grades C: laranja.
  - Grade T: azul/ciano.
  - RMA: vermelho.
- O item selecionado recebe fundo mais claro, texto branco e marcador discreto.
- O item sob o mouse recebe realce sem alterar o tamanho ou deslocar o menu.

## Comportamento

- As opcoes continuam sendo `GRADE A`, `GRADE B`, `GRADE C - PINTURA 1/2/3`, `GRADE T - TRIAGEM` e `RMA`.
- Clicar em uma opcao atualiza a referencia, a grade interna e o resumo da OS como ocorre hoje.
- Ao abrir o menu, a grade atual aparece selecionada.
- Nenhuma regra de observacoes, impressao ou cadastro da OS sera alterada.

## Implementacao

O `ContextMenuStrip` atual sera mantido, com a margem de imagem desativada e renderizacao visual personalizada para fundo, borda, selecao e barras de cor. A personalizacao ficara restrita ao seletor de grades para nao afetar outros menus.

## Verificacao

- Teste estatico confirma que a margem branca foi desativada e que o menu usa renderizacao personalizada.
- Parser PowerShell valida o script.
- Abertura visual confirma alinhamento, cores, hover e selecao nas sete opcoes.
- Os testes existentes de cadastro, grade e previa continuam passando.
