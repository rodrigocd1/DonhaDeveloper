# Salesforce Fields

## Account

| Campo | Tipo | Finalidade |
| --- | --- | --- |
| `Game_Player_Id__c` | Text(100), External ID, Unique | Identificador principal do jogador |
| `Game_Display_Name__c` | Text(80) | Nome exibido no jogo |
| `Game_Login_Provider__c` | Text(40) | Provider de login: guest, google, apple, steam |
| `Game_Google_Id__c` | Text(255) | ID Google vinculado |
| `Game_Apple_Id__c` | Text(255) | ID Apple vinculado |
| `Game_Steam_Id__c` | Text(255) | ID Steam vinculado |
| `Game_Profile_JSON__c` | Long Text Area | Perfil compacto do jogador |
| `Game_Progress_JSON__c` | Long Text Area | Progresso compacto do jogador |
| `Game_Rewards_JSON__c` | Long Text Area | Estado de recompensas e codigos resgatados |
| `Game_Feedback_JSON__c` | Long Text Area | Reserva para snapshot leve de feedback do jogador |
| `Game_Recovery_Hash__c` | Text(255) | Hash da chave de recovery |
| `Game_Recovery_Code_Created_At__c` | DateTime | Data da ultima geracao do hash |
| `Game_Passe_VIP_Active__c` | Checkbox | Indica VIP ativo |
| `Game_Passe_VIP_Expires_At__c` | DateTime | Expiracao do VIP |
| `Game_Last_Login_At__c` | DateTime | Ultimo login sincronizado |
| `Game_Last_Device_Id__c` | Text(255) | Ultimo device id conhecido |
| `Game_Is_Beta_Tester__c` | Checkbox | Marca usuario beta tester |
| `Game_Ranked_Points__c` | Number(18,0) | Pontos ranqueados |
| `Game_Ranked_Rank__c` | Text(80) | Faixa/rank atual |
| `Game_Ranked_JSON__c` | Long Text Area | Estado detalhado do ranked |
| `Game_Timer_Attack_JSON__c` | Long Text Area | Estado detalhado do modo Timer Attack |
| `Game_Nerves_Of_Steel_JSON__c` | Long Text Area | Estado detalhado do modo Nerves of Steel |
| `Game_Use_SSO_Photo_In_Ranking__c` | Checkbox | Preferencia de foto SSO no ranking |
| `Game_Config_JSON__c` | Long Text Area | Config global armazenada na Account `GAME_CONFIG` |

## Case

| Campo | Tipo | Finalidade |
| --- | --- | --- |
| `Game_Mode__c` | Text(80) | Modo de jogo informado pelo app |
| `Game_Player_Id__c` | Text(100) | PlayerId recebido no payload |
| `Game_Player_Account__c` | Lookup(Account) | Lookup direto para a conta do jogador |
| `Game_Feedback_Category__c` | Text(80) | Categoria do feedback ou evento de laboratorio |
| `Game_Feedback_Stars__c` | Number(1,0) | Avaliacao numerica |
| `Game_Feedback_Comment__c` | Long Text Area | Comentario livre do jogador |
| `Game_Board_Name__c` | Text(120) | Nome do tabuleiro |
| `Game_Stage_Number__c` | Number(18,0) | Estagio/fase jogada |
| `Game_Difficulty__c` | Text(80) | Dificuldade usada na partida |
| `Game_Player_Score__c` | Number(18,0) | Pontuacao do jogador |
| `Game_Ai_Score__c` | Number(18,0) | Pontuacao da IA |
| `Game_Result__c` | Text(80) | Resultado da partida |
| `Game_Match_Duration_Seconds__c` | Number(18,2) | Duracao da partida |
| `Game_Ai_Average_Time_Ms__c` | Number(18,2) | Tempo medio da IA |
| `Game_Ai_Max_Time_Ms__c` | Number(18,2) | Tempo maximo da IA |
| `Game_Powers_Used_JSON__c` | Long Text Area | Poderes usados na partida |
| `Game_Lab_Payload_JSON__c` | Long Text Area | Payload tecnico de laboratorio |
| `Game_App_Version__c` | Text(40) | Versao do app |
| `Game_Device_Info__c` | Long Text Area | Snapshot tecnico do device |
| `Game_Source__c` | Text(80) | Origem do evento no app |

## Observacoes

- `GAME_CONFIG` deve existir como `Account` manual.
- `Game_Config_JSON__c` guarda configuracao global e reward codes.
- `Origin` do `Case` tenta usar `Game` e faz fallback para `Web` se a picklist da org nao tiver `Game`.
- `Status` do `Case` tenta usar `New` e faz fallback para o primeiro valor ativo da org.
