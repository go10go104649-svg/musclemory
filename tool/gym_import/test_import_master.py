import copy
import tempfile
import unittest
from pathlib import Path
from openpyxl import Workbook
from import_master import read_master, prepare, normalized, sql_for

class ImportTests(unittest.TestCase):
    def setUp(self):
        self.tables = {'店舗':[dict(gym_id='s',gym_chain='Gym',gym_name="O'Brien 店",prefecture='県',municipality='市',machine_data_status='published')],
          '設備マスター':[dict(equipment_id='e',normalized_name='ダンベル',category='フリーウェイト',load_type='free_weight',needs_review=False)],
          '店舗設備':[dict(gym_id='s',equipment_id='e',raw_name='ダンベル',available=True,quantity=None)],'sheets':[]}
        self.catalog={'exercises':[dict(exerciseId='curl')]}
    def payload(self,t=None,m=None): return prepare(t or self.tables,'gym','Gym',m or [],self.catalog)
    def test_nulls_stable_keys_and_unmapped(self):
        a=self.payload(); b=self.payload()
        self.assertEqual(a,b)
        self.assertIsNone(a['gym_stores'][0]['station'])
        self.assertIsNone(a['gym_store_equipment'][0]['quantity'])
        self.assertIsNone(a['equipment'][0]['manufacturer'])
        self.assertEqual(a['equipment_exercise_mapping'],[])
        self.assertIn('on conflict (store_id,equipment_id)',sql_for(a))
        self.assertIn("O''Brien",sql_for(a))
    def test_duplicate_and_orphan_rejected(self):
        for table in ['店舗','設備マスター','店舗設備']:
            t=copy.deepcopy(self.tables); t[table].append(t[table][0].copy())
            with self.assertRaises(ValueError):self.payload(t)
        t=copy.deepcopy(self.tables);t['店舗設備'][0]['equipment_id']='missing'
        with self.assertRaises(ValueError):self.payload(t)
    def test_invalid_quantity_and_unknown_mapping_rejected(self):
        for value in [0,-1,1.2,'2',True]:
            t=copy.deepcopy(self.tables);t['店舗設備'][0]['quantity']=value
            with self.assertRaises(ValueError):self.payload(t)
        m=[dict(equipment_id='e',expected_name='ダンベル',expected_load_type='free_weight',exercise_ids=['missing'],rationale='test')]
        with self.assertRaises(ValueError):self.payload(m=m)
    def test_normalization_does_not_merge_ids(self):
        self.assertEqual(normalized(' ＡＢＣ　 24 '),'ABC 24')
        t=copy.deepcopy(self.tables);t['設備マスター'].append(dict(t['設備マスター'][0],equipment_id='e2'))
        self.assertEqual(len(self.payload(t)['equipment']),2)
    def test_read_xlsx_without_modification(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'input.xlsx';w=Workbook();w.remove(w.active)
            for name,rows in self.tables.items():
                if name=='sheets':continue
                s=w.create_sheet(name);s.append(list(rows[0]));s.append(list(rows[0].values()))
            w.save(path);before=path.read_bytes()
            t=read_master(path);self.assertEqual(len(self.payload(t)['gym_stores']),1)
            self.assertEqual(path.read_bytes(),before)
if __name__=='__main__': unittest.main()
