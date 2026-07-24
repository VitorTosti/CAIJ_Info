# Localizacao obrigatoria no cadastro de OS

## Objetivo

Garantir que todo produto adicionado automaticamente a uma ordem de servico pelo
InfoNotebook seja persistido no VHSYS com a localizacao `TECNICA_BT`, identificada
pelo almoxarifado `31196`.

## Comportamento

O servidor continuara enviando a localizacao junto ao produto da OS, mas nao
repetira o cadastro sem localizacao quando o VHSYS rejeitar a primeira tentativa.
A OS somente sera apresentada como concluida quando uma consulta posterior
confirmar que o produto possui `json_localizacoes` com o almoxarifado `31196`.

Se o VHSYS rejeitar a localizacao ou responder com o produto sem a associacao, o
job de triagem terminara com falha e exibira uma mensagem clara. A resposta real
da API sera preservada no diagnostico, sem expor as credenciais.

## Fluxo

1. Criar a OS no VHSYS.
2. Adicionar o produto com `TECNICA_BT` e almoxarifado `31196`.
3. Consultar os produtos da OS criada.
4. Confirmar o produto e sua localizacao.
5. Somente entao adicionar os servicos e concluir o job.

O servidor nao apagara automaticamente uma OS criada parcialmente. Isso evita
exclusoes silenciosas e preserva o numero para correcao manual quando a API
externa falhar.

## Validacao

Os testes automatizados devem comprovar que:

- o payload inclui a localizacao obrigatoria;
- nao existe nova tentativa sem localizacao;
- produto sem `json_localizacoes` causa falha;
- produto com almoxarifado `31196` permite concluir o cadastro;
- a mensagem de erro identifica a ausencia da localizacao.

Tambem devem ser executados o parser de PowerShell e os testes existentes de
integracao do Altertag antes da atualizacao do servidor operacional.
