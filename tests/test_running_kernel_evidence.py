"""Kernel observations never borrow /boot from a container userspace."""
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
source = (ROOT/'firulaiAgent.sh').read_text(encoding='utf8').split("<<'PY_RUNNING_KERNEL'\n",1)[1].split('\nPY_RUNNING_KERNEL',1)[0]
ns = dict(__name__='kernel_evidence_test')
exec(compile(source, 'embedded-kernel-observer', 'exec'), ns)


class RunningKernelEvidenceTests(unittest.TestCase):
    def collect(self, isolation=(1,'none'), file_evidence=True):
        commands=[];files=[]
        def command(args):
            commands.append(args)
            if args[0]=='systemd-detect-virt':return isolation
            if args[1]=='-S':return 0,'example-image: /boot/vmlinuz-8.2.0-5-example'
            return 0,'example-image\t8.2.0-5.1\tamd64\texample-source\t8.2.0-5.1\tinstalled'
        def file(path,limit,compressed=False):
            files.append(path)
            if not file_evidence or path=='/proc/config.gz':return None
            return dict(path=path,sha256='a'*64,size_bytes=100)
        host=SimpleNamespace(system=lambda:'Linux',release=lambda:'8.2.0-5-example',machine=lambda:'x86_64',version=lambda:'SMP example')
        with patch.dict(ns,platform=host,kernel_command=command,kernel_file=file), patch.object(Path,'exists',return_value=False):
            result=ns['collect_kernel_evidence']()
        return result,commands,files

    def test_host_retains_release_bound_image_config_and_package_metadata(self):
        result,commands,files=self.collect()
        self.assertEqual(result['environment']['scope'],'host')
        self.assertEqual(result['config']['origin'],'installed_boot_file')
        self.assertEqual(result['image']['path'],'/boot/vmlinuz-'+result['release'])
        self.assertEqual(result['package']['source_package'],'example-source')
        self.assertEqual(result['errors'],[])

    def test_container_never_uses_its_boot_files_or_package_database_as_host_evidence(self):
        result,commands,files=self.collect((0,'lxc'))
        self.assertEqual(result['environment'],dict(scope='container',container='lxc'))
        self.assertEqual(files,['/proc/config.gz'])
        self.assertEqual(len(commands),1)
        self.assertIsNone(result['image'])
        self.assertIsNone(result['package'])

    def test_missing_isolation_detector_stays_unknown(self):
        result,commands,files=self.collect((None,''))
        self.assertEqual(result['environment']['scope'],'unknown')
        self.assertEqual(files,['/proc/config.gz'])
        self.assertEqual(len(commands),1)

    def test_missing_files_are_observation_gaps_not_unaffected_verdicts(self):
        result,_,_=self.collect(file_evidence=False)
        self.assertIsNone(result['config'])
        self.assertIsNone(result['image'])
        self.assertIn('kernel_config_unavailable',result['errors'])
        self.assertNotIn('state',result)

    def test_running_config_is_distinguished_from_installed_boot_config(self):
        host=SimpleNamespace(system=lambda:'Linux',release=lambda:'8.2.0-5-example',machine=lambda:'x86_64',version=lambda:'SMP')
        def file(path,*args,**kwargs):return dict(path=path,sha256='a'*64,size_bytes=100)
        with patch.dict(ns,platform=host,kernel_file=file,kernel_command=lambda args:(0,'lxc')):
            result=ns['collect_kernel_evidence']()
        self.assertEqual(result['config']['origin'],'running_kernel')
        self.assertEqual(result['config']['path'],'/proc/config.gz')
        self.assertIsNone(result['image'])

    def test_reboot_during_capture_discards_the_observation(self):
        host=SimpleNamespace(system=lambda:'Linux',release=unittest.mock.Mock(side_effect=['8.2.0-5-example','8.2.0-6-example']),machine=lambda:'x86_64',version=lambda:'SMP')
        with patch.dict(ns,platform=host,kernel_command=lambda args:(0,'lxc'),kernel_file=lambda *args,**kwargs:None):
            self.assertEqual(ns['collect_kernel_evidence'](),{})

    def test_unsafe_release_cannot_construct_a_boot_path(self):
        host=SimpleNamespace(system=lambda:'Linux',release=lambda:'8.2/../../etc/passwd',machine=lambda:'x86_64')
        with patch.dict(ns,platform=host):self.assertEqual(ns['collect_kernel_evidence'](),{})

    def test_file_measurement_is_bounded_and_hashed(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'fixture'
            path.write_bytes(b'kernel-file')
            self.assertIsNone(ns['kernel_file'](path,4))
            measured=ns['kernel_file'](path,100)
            self.assertEqual(measured['size_bytes'],11)
            self.assertEqual(len(measured['sha256']),64)


if __name__=='__main__':unittest.main()
