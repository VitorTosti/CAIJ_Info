# Seletor de grades e ajustes da triagem

## Objetivo

Melhorar o cadastro de OS para permitir a escolha direta de qualquer grade,
mostrar o tecnico Erick e tratar Grade T como triagem sem exigir observacoes.
Na etiqueta, o texto da Grade T deve caber integralmente no selo superior.

## Seletor de grade no cadastro

O card `REFERENCIA` da tela `Cadastrar OS Altertag` deixara de ser uma caixa de
texto livre e passara a ser um botao. Ao clicar, ele abrira um menu com:

- `GRADE A`
- `GRADE B`
- `GRADE C - PINTURA 1`
- `GRADE C - PINTURA 2`
- `GRADE C - PINTURA 3`
- `GRADE T - TRIAGEM`
- `RMA`

A escolha atualizara o resumo visivel e o valor enviado ao VHSYS. O menu usara a
grade atual como selecao inicial e nao alterara a grade se for fechado sem uma
escolha.

## Tecnicos

O card `TECNICO` exibira quatro botoes: `Lucas`, `Hyrides`, `Vitor` e `Erick`.
Os botoes serao redistribuidos dentro da largura atual do card, preservando o
estado selecionado e o envio do nome ao servidor.

## Regra de observacoes

Observacoes continuarao obrigatorias para Grade B e todas as variacoes de Grade
C. Grade T - Triagem nao exigira observacoes e o botao de impressao devera ficar
disponivel mesmo quando o campo estiver vazio.

Essa regra sera aplicada em todas as validacoes da janela, evitando diferenca
entre o estado visual do botao e a validacao executada ao confirmar.

## Etiqueta

Na interface e no cadastro da OS, a referencia permanecera `GRADE T - TRIAGEM`.
Somente no selo superior da previa e da etiqueta impressa o texto sera reduzido
para `T - TRIAGEM`.

As demais grades manterao os textos atuais, incluindo
`GRADE C - PINTURA 1/2/3`.

## Validacao

Os testes devem confirmar:

- o menu contem todas as grades e variacoes de pintura;
- Erick aparece e pode ser selecionado no card de tecnicos;
- Grade T com observacoes vazias permite imprimir;
- Grade B e Grade C sem observacoes continuam bloqueadas;
- a previa e o TSPL usam `T - TRIAGEM`;
- o servidor continua recebendo e normalizando `T - TRIAGEM`.
