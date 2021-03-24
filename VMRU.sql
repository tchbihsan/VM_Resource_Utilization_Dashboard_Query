WITH ADL AS 
(
SELECT DISTINCT ACC.[DBM_ID], ACC.[DBM_Person_Name] AS ADL_NAME ,ACC.[DBM_Person_Email]  AS ADL_EMAIL
FROM 
[shared].[DBM_All_Applications_All_Components_Contacts]  ACC  WITH(NOLOCK)
LEFT JOIN 
[shared].[ITSM_CMDB_Applications_RelatedTo_Servers] CAS  WITH (NOLOCK) 
ON CAS.Carta_App_Status=ACC.DBM_ID 
WHERE ACC.[DBM_Role_Type] = 'ADL' 
and
ACC.[DBM_ID] LIKE 'APP%'
),

SME AS 
(
	SELECT DISTINCT ACC.[DBM_ID], ACC.[DBM_Person_Name] AS SME_NAME ,ACC.[DBM_Person_Email]  AS SME_EMAIL
	FROM [shared].[DBM_All_Applications_All_Components_Contacts]  ACC WITH(NOLOCK)
	LEFT JOIN 
	[shared].[ITSM_CMDB_Applications_RelatedTo_Servers] CAS   WITH (NOLOCK) 
	ON CAS.Carta_ID=ACC.DBM_ID 
	WHERE ACC.[DBM_Role_Type] = 'SME' 
	AND ACC.[DBM_ID] LIKE 'APP%'
),

BO AS 
(
SELECT DISTINCT ACC.[DBM_ID],ACC.[DBM_Organization_Name] [BO Org Name] 
FROM  
[shared].[DBM_All_Applications_All_Components_Contacts]  ACC  WITH(NOLOCK) 
LEFT JOIN
[shared].[ITSM_CMDB_Applications_RelatedTo_Servers] CAS   WITH(NOLOCK)
ON CAS.Carta_ID=ACC.DBM_ID 
WHERE ACC.[DBM_Role_Type] = 'Business Owner' 
and
ACC.[DBM_ID] LIKE 'APP%'
),

APPs AS (
	SELECT br.[Source_ReconciliationIdentity] as server_recon_id, 
	 app.CI_Name AS [Application Name],
	 app.Serial_Number AS [Application ID],
	 app.Environment,
	 app.Status
	FROM [shared].[z_ITSM_CMDB_Applications] app
	LEFT JOIN [shared].[z_ITSM_CMDB_BaseRelationship] BR 
		on BR.Destination_ReconciliationIden = APP.reconciliationidentity AND BR.Source_ClassID = 'BMC_COMPUTERSYSTEM' AND BR.Destination_ClassId IN ('BMC_APPLICATION')
	WHERE
	APP.Status = 'Deployed'
	AND app.Category = 'Software'
	AND app.Serial_Number like 'app-%'
),

VMs AS (
	SELECT DISTINCT CS2.Name AS [VM Full Name]--where you want all the columns to be displayed      
	 ,UPPER(CS2.HostName) AS [VM Name]
	 ,CS2.ReconciliationIdentity AS [VM Recon Identity] --unique id
	 ,CASE              
		WHEN CHARINDEX('.',CS1.Name,1) < 1 AND (CS1.Domain IS NOT NULL AND CS1.Domain != '') THEN CS1.Hostname + '.' + CS1.Domain
		ELSE CS1.Name       
		END AS [VMHost Name]
	,CL.Name AS [VMCluster Name]   
	,CS2.SystemRole   
	,CS2.Status AS [VM Status]
	,CS2.XOM_Capability AS [VM Capability]
	,CS2.XOM_Program AS [VM Program]
	,CS2.XOM_Server_OS_Relationship AS [Operating System]
	--,CS2.XOM_Ops_Supported_By AS [Support Group]
	,AP.Full_Name as [Support Group]
	FROM ITDW.Shared.z_ITSM_CMDB_ComputerSystem CS1 --merging columns of different views--column of one view should be matching with the other.       
	LEFT OUTER JOIN ITDW.Shared.z_ITSM_CMDB_BASeRelationship BR1  --table for relationships            
		ON CS1.InstanceId = BR1.Source_InstanceId       
	LEFT OUTER JOIN ITDW.Shared.z_ITSM_CMDB_ComputerSystem CS2              
		ON BR1.Destination_InstanceID = CS2.InstanceID
		AND CS1.Type = 'Processing Unit'       
	LEFT OUTER JOIN ITDW.Shared.z_ITSM_CMDB_BASeRelationship BR2             
		ON BR1.Source_InstanceId = BR2.Destination_InstanceId              
		AND BR2.Source_ClASsId = 'BMC_Cluster'       
	LEFT OUTER JOIN ITDW.Shared.z_ITSM_CMDB_Cluster CL
		ON BR2.Source_InstanceId = CL.InstanceId
	LEFT JOIN [shared].[z_ITSM_CMDB_AssetPeople] AP 
		ON AP.[AssetInstanceID] = CS2.[ReconciliationIdentity] 
	WHERE CS2.ManufacturerName = 'VMware'
	AND AP.Form_Type = 'Support Group' 
),

CRQs AS (
	SELECT main.Change_ID, main.Scheduled_End_Date, main.Status, main.Template, rel.Relationship_ID, 
	CASE 
		WHEN main.Template = 'SVR-WIN-Virtual Machine Resource Change' THEN 'Rightsizing'
		WHEN main.Template in ('SVR-WIN-R-Retire Virtual Server Automated','SVR-WIN-R-Retire Server') THEN 'Decommission'
		ELSE NULL
		END AS [Activity Type]
	FROM [shared].[ITSM_CHG_MAIN] main
	INNER JOIN [shared].[ITSM_CHG_REL] rel
		ON main.change_id=rel.change_id
	WHERE Template in ('SVR-WIN-Virtual Machine Resource Change', 'SVR-WIN-R-Retire Virtual Server Automated','SVR-WIN-R-Retire Server')
	AND main.Scheduled_Start_Date >= '2020-05-01'
)

-----------------------------------------------------------------------------------------------------------
SELECT vms.*
,APP_DATA.*
,ADL.ADL_NAME
,SME.SME_NAME
,BO.[BO Org Name]
,CRQs.*
,Team = 'Brownfield'
FROM VMs vms
LEFT JOIN APPs APP_DATA ON vms.[VM Recon Identity]=APP_DATA.server_recon_id
LEFT JOIN ADL ON ADL.DBM_id=APP_DATA.[Application ID]
LEFT JOIN SME ON SME.DBM_id=APP_DATA.[Application ID]
LEFT JOIN BO  ON BO.DBM_id=APP_DATA.[Application ID]
LEFT JOIN CRQs ON CRQs.Relationship_ID=vms.[VM Recon Identity]
WHERE vms.[VM Status] <> 'End of Life'
