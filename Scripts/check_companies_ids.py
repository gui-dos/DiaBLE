import yaml
import json

# https://bitbucket.org/bluetooth-SIG/public/src/main/assigned_numbers/company_identifiers/company_identifiers.yaml
# https://github.com/NordicSemiconductor/bluetooth-numbers-database/blob/master/v1/company_ids.json

with open('company_identifiers.yaml', 'r') as file:
    companies_yaml= yaml.safe_load(file)
    
with open('company_ids.json', 'r') as file:
    companies_json = json.load(file)
    
company_yaml_dict = {}
for company in companies_yaml['company_identifiers']:
    company_yaml_dict[company['value']] = company['name']
    
for company in companies_json:
    if company['name'] != company_yaml_dict.get(company['code'], company['name'] + " NOT FOUND"):
        print(f"{company['code']} ({hex(company['code'])}): {company['name']} != {company_yaml_dict.get(company['code'], company['name'] + ' NOT FOUND')}")
        
newest_number = companies_yaml['company_identifiers'][0]['value']
        
new_companies_count = newest_number - len(companies_json) + 2

if new_companies_count > 0:
    for company in reversed(companies_yaml['company_identifiers'][:new_companies_count]):
        print(f'    {{ "code": {company["value"]}, "name": "{company["name"]}" }},')